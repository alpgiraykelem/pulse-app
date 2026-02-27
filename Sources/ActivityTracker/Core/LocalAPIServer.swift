import Foundation
import Network

final class LocalAPIServer {
    private var listener: NWListener?
    private let store: ActivityStore
    private let projectMatcher: ProjectMatcher
    private(set) var port: Int = 18492

    init(store: ActivityStore, projectMatcher: ProjectMatcher) {
        self.store = store
        self.projectMatcher = projectMatcher
    }

    func start() {
        for tryPort in 18492...18499 {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let nwPort = NWEndpoint.Port(rawValue: UInt16(tryPort))!
                let l = try NWListener(using: params, on: nwPort)

                l.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.port = tryPort
                        print("[API] Server listening on 127.0.0.1:\(tryPort)")
                    case .failed(let error):
                        print("[API] Listener failed: \(error)")
                    default:
                        break
                    }
                }

                l.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }

                l.start(queue: .global(qos: .userInitiated))
                listener = l
                port = tryPort
                return
            } catch {
                continue
            }
        }
        print("[API] Could not bind to any port in range 18492-18499")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveHTTPRequest(connection)
    }

    private func receiveHTTPRequest(_ connection: NWConnection) {
        receiveData(connection: connection, accumulated: Data())
    }

    private func receiveData(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }

            var data = accumulated
            if let content = content { data.append(content) }

            if data.isEmpty {
                if isComplete { connection.cancel(); return }
                self.receiveData(connection: connection, accumulated: data)
                return
            }

            let separator = Data("\r\n\r\n".utf8)
            guard let sepRange = data.range(of: separator) else {
                if isComplete {
                    self.processRequest(data, connection: connection)
                } else if data.count < 65536 {
                    self.receiveData(connection: connection, accumulated: data)
                } else {
                    connection.cancel()
                }
                return
            }

            // Headers complete — calculate body bytes received
            let headerBytes = data.distance(from: data.startIndex, to: sepRange.lowerBound)
            let separatorBytes = 4 // \r\n\r\n
            let bodyBytesReceived = data.count - headerBytes - separatorBytes

            // Parse Content-Length from headers
            var expectedBodyLength = 0
            let headerData = data[data.startIndex..<sepRange.lowerBound]
            if let headerStr = String(data: headerData, encoding: .utf8)?.lowercased() {
                if let clRange = headerStr.range(of: "content-length:") {
                    let afterCL = headerStr[clRange.upperBound...].drop(while: { $0 == " " })
                    let clLine = afterCL.prefix(while: { $0 >= "0" && $0 <= "9" })
                    expectedBodyLength = Int(clLine) ?? 0
                }
            }

            if expectedBodyLength > 0 && bodyBytesReceived < expectedBodyLength && !isComplete {
                self.receiveData(connection: connection, accumulated: data)
                return
            }

            self.processRequest(data, connection: connection)
        }
    }

    private func processRequest(_ data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let response = self.routeRequest(requestString)
        let httpResponse = self.buildHTTPResponse(response)

        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Routing

    private struct APIResponse {
        let status: Int
        let body: String
        let contentType: String

        init(status: Int, body: String, contentType: String = "application/json; charset=utf-8") {
            self.status = status
            self.body = body
            self.contentType = contentType
        }

        static func ok(_ json: String) -> APIResponse { APIResponse(status: 200, body: json) }
        static func created(_ json: String) -> APIResponse { APIResponse(status: 201, body: json) }
        static func badRequest(_ msg: String) -> APIResponse { APIResponse(status: 400, body: "{\"error\":\"\(msg)\"}") }
        static func notFound() -> APIResponse { APIResponse(status: 404, body: "{\"error\":\"not found\"}") }
    }

    /// Parse JSON body tolerantly — handles both `"id": 5` and `"id": "5"`
    private func parseBody<T: Decodable>(_ body: String, as type: T.Type) -> T? {
        guard let data = body.data(using: .utf8) else { return nil }
        // First try normal decode
        if let result = try? JSONDecoder().decode(type, from: data) {
            return result
        }
        // Fallback: convert string numbers to actual numbers in JSON
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var fixed = obj
            for (key, val) in obj {
                if let str = val as? String, let num = Int64(str) {
                    fixed[key] = num
                }
            }
            if let fixedData = try? JSONSerialization.data(withJSONObject: fixed),
               let result = try? JSONDecoder().decode(type, from: fixedData) {
                return result
            }
        }
        return nil
    }

    private func routeRequest(_ raw: String) -> APIResponse {
        let lines = raw.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return .badRequest("empty request") }

        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return .badRequest("malformed request") }

        let method = String(parts[0])
        let path = String(parts[1])

        // Handle CORS preflight
        if method == "OPTIONS" {
            return .ok("")
        }

        // Extract JSON body — trim null bytes and whitespace
        let body: String
        if let bodyStart = raw.range(of: "\r\n\r\n") {
            let rawBody = String(raw[bodyStart.upperBound...])
            body = rawBody.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(["\0"])))
        } else {
            body = ""
        }
        // Parse query string
        let pathOnly: String
        let queryParams: [String: String]
        if let qIndex = path.firstIndex(of: "?") {
            pathOnly = String(path[path.startIndex..<qIndex])
            let queryString = String(path[path.index(after: qIndex)...])
            var params: [String: String] = [:]
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    params[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
            queryParams = params
        } else {
            pathOnly = path
            queryParams = [:]
        }

        switch (method, pathOnly) {
        case ("GET", "/report"):
            return handleServeReport(params: queryParams)
        case ("GET", "/api/days"):
            return handleGetDays()
        case ("GET", "/api/report"):
            return handleGetReport(params: queryParams)
        case ("GET", "/api/report/week"):
            return handleGetWeekReport(params: queryParams)
        case ("GET", "/api/report/month"):
            return handleGetMonthReport(params: queryParams)
        case ("GET", "/api/app"):
            return handleGetApp(params: queryParams)
        case ("GET", "/api/brand/detail"):
            return handleGetBrandDetail(params: queryParams)
        case ("GET", "/api/projects"):
            return handleGetProjects()
        case ("POST", "/api/classify"):
            return handleClassify(body: body)
        case ("POST", "/api/brand"):
            return handleCreateBrand(body: body)
        case ("POST", "/api/project"):
            return handleCreateProject(body: body)
        case ("POST", "/api/rule"):
            return handleCreateRule(body: body)
        case ("POST", "/api/auto-assign"):
            return handleAutoAssign(body: body)
        case ("POST", "/api/brand/update"):
            return handleUpdateBrand(body: body)
        case ("POST", "/api/brand/merge"):
            return handleMergeBrand(body: body)
        case ("POST", "/api/brand/delete"):
            return handleDeleteBrand(body: body)
        case ("POST", "/api/project/update"):
            return handleUpdateProject(body: body)
        case ("POST", "/api/project/delete"):
            return handleDeleteProject(body: body)
        case ("GET", "/api/rules"):
            return handleGetRules()
        case ("POST", "/api/rule/delete"):
            return handleDeleteRule(body: body)
        case ("GET", "/api/suggestions"):
            return handleGetSuggestions()
        case ("POST", "/api/suggestion/accept"):
            return handleAcceptSuggestion(body: body)
        case ("POST", "/api/suggestion/dismiss"):
            return handleDismissSuggestion(body: body)
        default:
            return .notFound()
        }
    }

    // MARK: - Handlers

    private func handleGetProjects() -> APIResponse {
        do {
            let brandList = try store.allBrands()
            let projectList = try store.allProjects()

            let brandsJSON = brandList.map { b in
                "{\"id\":\(b.id),\"name\":\(jsonString(b.name)),\"color\":\(jsonString(b.color))}"
            }.joined(separator: ",")

            let projectsJSON = projectList.map { (p, brandName) in
                "{\"id\":\(p.id),\"brandId\":\(p.brandId),\"brandName\":\(jsonString(brandName)),\"name\":\(jsonString(p.name)),\"color\":\(jsonString(p.color))}"
            }.joined(separator: ",")

            return .ok("{\"brands\":[\(brandsJSON)],\"projects\":[\(projectsJSON)]}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleClassify(body: String) -> APIResponse {
        struct ClassifyRequest: Decodable {
            let activityIds: [Int64]
            let projectId: Int64
            let createRule: Bool?
            let ruleType: String?
            let rulePattern: String?
        }

        guard let req = parseBody(body, as: ClassifyRequest.self) else {
            return .badRequest("invalid JSON")
        }

        do {
            try store.bulkUpdateProjectAssignment(activityIds: req.activityIds, projectId: req.projectId, source: .manual)

            if req.createRule == true, let typeStr = req.ruleType, let pattern = req.rulePattern,
               let ruleType = RuleType(rawValue: typeStr) {
                try store.insertRule(projectId: req.projectId, ruleType: ruleType, pattern: pattern)
                projectMatcher.reloadRules()
            }

            return .ok("{\"classified\":\(req.activityIds.count)}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleCreateBrand(body: String) -> APIResponse {
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct CreateBrandRequest: Decodable {
            let name: String
            let color: String?
        }

        guard let req = try? JSONDecoder().decode(CreateBrandRequest.self, from: data) else {
            return .badRequest("invalid JSON")
        }

        do {
            let id = try store.insertBrand(name: req.name, color: req.color ?? "#6366f1")
            return .created("{\"id\":\(id),\"name\":\(jsonString(req.name))}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleCreateProject(body: String) -> APIResponse {
        struct CreateProjectRequest: Decodable {
            let brandId: Int64
            let name: String
            let color: String?
        }

        guard let req = parseBody(body, as: CreateProjectRequest.self) else {
            return .badRequest("invalid JSON")
        }

        do {
            let id = try store.insertProject(brandId: req.brandId, name: req.name, color: req.color ?? "#6366f1")
            return .created("{\"id\":\(id),\"name\":\(jsonString(req.name))}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleCreateRule(body: String) -> APIResponse {
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct CreateRuleRequest: Decodable {
            let projectId: Int64
            let ruleType: String
            let pattern: String
            let isRegex: Bool?
            let priority: Int?
        }

        guard let req = try? JSONDecoder().decode(CreateRuleRequest.self, from: data),
              let ruleType = RuleType(rawValue: req.ruleType) else {
            return .badRequest("invalid JSON or ruleType")
        }

        do {
            let id = try store.insertRule(
                projectId: req.projectId,
                ruleType: ruleType,
                pattern: req.pattern,
                isRegex: req.isRegex ?? false,
                priority: req.priority ?? 0
            )
            projectMatcher.reloadRules()
            return .created("{\"id\":\(id)}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleAutoAssign(body: String) -> APIResponse {
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct AutoAssignRequest: Decodable {
            let date: String?
        }

        let req = try? JSONDecoder().decode(AutoAssignRequest.self, from: data)
        let count = projectMatcher.autoAssignUnclassified(date: req?.date)
        return .ok("{\"assigned\":\(count)}")
    }

    private func handleUpdateBrand(body: String) -> APIResponse {
        struct Req: Decodable { let id: Int64; let name: String?; let color: String? }
        guard let req = parseBody(body, as: Req.self) else {
            return .badRequest("invalid JSON")
        }
        do {
            try store.updateBrand(id: req.id, name: req.name, color: req.color)
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleDeleteBrand(body: String) -> APIResponse {
        struct Req: Decodable { let id: Int64 }
        guard let req = parseBody(body, as: Req.self) else {
            return .badRequest("invalid JSON: \(body)")
        }
        do {
            try store.deleteBrand(id: req.id)
            projectMatcher.reloadRules()
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleMergeBrand(body: String) -> APIResponse {
        struct Req: Decodable { let sourceId: Int64; let targetId: Int64 }
        guard let req = parseBody(body, as: Req.self) else {
            return .badRequest("invalid JSON")
        }
        guard req.sourceId != req.targetId else {
            return .badRequest("source and target must be different")
        }
        do {
            try store.mergeBrands(sourceId: req.sourceId, targetId: req.targetId)
            projectMatcher.reloadRules()
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleUpdateProject(body: String) -> APIResponse {
        struct Req: Decodable { let id: Int64; let name: String?; let color: String?; let brandId: Int64? }
        guard let req = parseBody(body, as: Req.self) else {
            return .badRequest("invalid JSON")
        }
        do {
            try store.updateProject(id: req.id, name: req.name, color: req.color, brandId: req.brandId)
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleDeleteProject(body: String) -> APIResponse {
        struct Req: Decodable { let id: Int64 }
        guard let req = parseBody(body, as: Req.self) else {
            return .badRequest("invalid JSON: \(body)")
        }
        do {
            try store.deleteProject(id: req.id)
            projectMatcher.reloadRules()
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleGetRules() -> APIResponse {
        do {
            let rules = try store.loadAllProjectRules()
            let allProjects = try store.allProjects()
            let projectNames: [Int64: String] = Dictionary(
                allProjects.map { ($0.project.id, "\($0.brandName) > \($0.project.name)") },
                uniquingKeysWith: { first, _ in first }
            )
            let rulesJSON = rules.map { r in
                let label = projectNames[r.projectId] ?? "Unknown"
                return "{\"id\":\(r.id),\"projectId\":\(r.projectId),\"projectLabel\":\(jsonString(label)),\"ruleType\":\(jsonString(r.ruleType.rawValue)),\"pattern\":\(jsonString(r.pattern)),\"isRegex\":\(r.isRegex),\"priority\":\(r.priority)}"
            }.joined(separator: ",")
            return .ok("{\"rules\":[\(rulesJSON)]}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleDeleteRule(body: String) -> APIResponse {
        struct Req: Decodable { let id: Int64 }
        guard let req = parseBody(body, as: Req.self) else {
            return .badRequest("invalid JSON")
        }
        do {
            try store.deleteRule(id: req.id)
            projectMatcher.reloadRules()
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    // MARK: - Serve Report HTML

    private func handleServeReport(params: [String: String]) -> APIResponse {
        // Generate or re-generate the SPA HTML
        let spaURL = HTMLReportGenerator.generateSPA(apiPort: port)

        guard let html = try? String(contentsOf: spaURL, encoding: .utf8) else {
            return .badRequest("Failed to read report.html")
        }

        // Inject initial date if provided
        let date = params["date"]
        let finalHTML: String
        if let date = date {
            finalHTML = html.replacingOccurrences(
                of: "var INITIAL_DATE = null;",
                with: "var INITIAL_DATE = '\(date)';"
            )
        } else {
            finalHTML = html
        }

        return APIResponse(status: 200, body: finalHTML, contentType: "text/html; charset=utf-8")
    }

    // MARK: - Report Data Handlers

    private func handleGetDays() -> APIResponse {
        do {
            let dates = try store.allDates()
            let datesJSON = dates.map { jsonString($0) }.joined(separator: ",")
            return .ok("{\"dates\":[\(datesJSON)]}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleGetReport(params: [String: String]) -> APIResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = params["date"] ?? formatter.string(from: Date())

        do {
            let summary = try store.queryDay(date: dateStr)
            let timeline = try store.queryTimeline(date: dateStr)
            let brandSummaries = try store.queryDayByProject(date: dateStr)
            let unassigned = try store.queryUnassignedActivities(date: dateStr)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            // Summary
            let summaryData = try encoder.encode(summary)
            let summaryJSON = String(data: summaryData, encoding: .utf8) ?? "{}"

            // Timeline
            let timelineData = try encoder.encode(timeline)
            let timelineJSON = String(data: timelineData, encoding: .utf8) ?? "[]"

            // Brand summaries
            let brandsData = try encoder.encode(brandSummaries)
            let brandsJSON = String(data: brandsData, encoding: .utf8) ?? "[]"

            // Unassigned
            let unassignedData = try encoder.encode(unassigned)
            let unassignedJSON = String(data: unassignedData, encoding: .utf8) ?? "[]"

            // Projects info
            let allBrands = try store.allBrands()
            let allProjects = try store.allProjects()
            let brandListJSON = allBrands.map { b in
                "{\"id\":\(b.id),\"name\":\(jsonString(b.name)),\"color\":\(jsonString(b.color))}"
            }.joined(separator: ",")
            let projectListJSON = allProjects.map { (p, brandName) in
                "{\"id\":\(p.id),\"brandId\":\(p.brandId),\"brandName\":\(jsonString(brandName)),\"name\":\(jsonString(p.name)),\"color\":\(jsonString(p.color))}"
            }.joined(separator: ",")

            // Assigned activity IDs (to filter from app cards)
            let assignedIds = try store.assignedActivityIds(date: dateStr)
            let assignedIdsJSON = assignedIds.map { String($0) }.joined(separator: ",")

            return .ok("{\"summary\":\(summaryJSON),\"timeline\":\(timelineJSON),\"brandSummaries\":\(brandsJSON),\"unassigned\":\(unassignedJSON),\"brands\":[\(brandListJSON)],\"projects\":[\(projectListJSON)],\"assignedIds\":[\(assignedIdsJSON)]}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleGetWeekReport(params: [String: String]) -> APIResponse {
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dateStr = params["date"] ?? formatter.string(from: Date())
            guard let targetDate = formatter.date(from: dateStr) else {
                return .badRequest("invalid date")
            }

            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: targetDate)
            let daysFromMonday = (weekday + 5) % 7
            guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: targetDate),
                  let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else {
                return .badRequest("date calculation error")
            }

            let summaries = try store.queryDays(from: formatter.string(from: monday), to: formatter.string(from: sunday))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summaries)
            let json = String(data: data, encoding: .utf8) ?? "[]"

            return .ok("{\"weekStart\":\(jsonString(formatter.string(from: monday))),\"weekEnd\":\(jsonString(formatter.string(from: sunday))),\"days\":\(json)}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleGetMonthReport(params: [String: String]) -> APIResponse {
        do {
            let calendar = Calendar.current
            let now = Date()
            let year = params["year"].flatMap { Int($0) } ?? calendar.component(.year, from: now)
            let month = params["month"].flatMap { Int($0) } ?? calendar.component(.month, from: now)

            let summaries = try store.queryMonth(year: year, month: month)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summaries)
            let json = String(data: data, encoding: .utf8) ?? "[]"

            let totalSeconds = summaries.reduce(0) { $0 + $1.totalSeconds }

            return .ok("{\"year\":\(year),\"month\":\(month),\"totalSeconds\":\(totalSeconds),\"days\":\(json)}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    // MARK: - App Detail Handler

    private func handleGetApp(params: [String: String]) -> APIResponse {
        guard let name = params["name"], !name.isEmpty else {
            return .badRequest("name parameter required")
        }
        do {
            let report = try store.queryAppDetail(appName: name, from: params["from"], to: params["to"])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return .ok(json)
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    // MARK: - Brand Detail Handler

    private func handleGetBrandDetail(params: [String: String]) -> APIResponse {
        guard let idStr = params["id"], let brandId = Int64(idStr) else {
            return .badRequest("id parameter required")
        }
        do {
            let detail = try store.queryBrandDetail(brandId: brandId, from: params["from"], to: params["to"])
            let jsonData = try JSONSerialization.data(withJSONObject: detail, options: [])
            let json = String(data: jsonData, encoding: .utf8) ?? "{}"
            return .ok(json)
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    // MARK: - Suggestion Handlers

    private func handleDismissSuggestion(body: String) -> APIResponse {
        struct Req: Decodable { let token: String }
        guard let req = parseBody(body, as: Req.self) else {
            return .badRequest("invalid JSON")
        }
        do {
            try store.dismissSuggestion(token: req.token)
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleGetSuggestions() -> APIResponse {
        let detector = PatternDetector(store: store)
        var brands = detector.detect()

        // Filter out dismissed suggestions
        let dismissed = (try? store.dismissedSuggestionTokens()) ?? []
        brands = brands.compactMap { brand in
            var b = brand
            b.projects = b.projects.filter { !dismissed.contains($0.fullToken) }
            return b.projects.isEmpty ? nil : b
        }

        let brandsJSON = brands.map { brand in
            let projectsJSON = brand.projects.map { proj in
                let rulesJSON = proj.suggestedRules.map { r in
                    "{\"ruleType\":\(jsonString(r.ruleType.rawValue)),\"pattern\":\(jsonString(r.pattern)),\"isRegex\":\(r.isRegex)}"
                }.joined(separator: ",")
                let appsArr = proj.apps.map { jsonString($0) }.joined(separator: ",")
                return "{\"suggestedName\":\(jsonString(proj.suggestedName)),\"fullToken\":\(jsonString(proj.fullToken)),\"activityCount\":\(proj.activityCount),\"apps\":[\(appsArr)],\"suggestedRules\":[\(rulesJSON)]}"
            }.joined(separator: ",")
            let appsArr = brand.apps.map { jsonString($0) }.joined(separator: ",")
            return "{\"suggestedName\":\(jsonString(brand.suggestedName)),\"rootToken\":\(jsonString(brand.rootToken)),\"totalActivities\":\(brand.totalActivities),\"apps\":[\(appsArr)],\"projects\":[\(projectsJSON)]}"
        }.joined(separator: ",")

        return .ok("{\"suggestions\":[\(brandsJSON)]}")
    }

    private func handleAcceptSuggestion(body: String) -> APIResponse {
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }

        struct AcceptRequest: Decodable {
            let brandName: String?
            let projectName: String?
            let rules: [RuleInput]?
            let existingProjectId: Int64?

            struct RuleInput: Decodable {
                let ruleType: String
                let pattern: String
                let isRegex: Bool?
            }
        }

        guard let req = try? JSONDecoder().decode(AcceptRequest.self, from: data) else {
            return .badRequest("invalid JSON")
        }

        do {
            let projectId: Int64

            if let existingId = req.existingProjectId {
                // Assign rules to existing project
                projectId = existingId
            } else {
                // Create brand + project
                guard let brandName = req.brandName, !brandName.isEmpty else {
                    return .badRequest("brandName required when not using existingProjectId")
                }
                let projName = req.projectName ?? brandName

                let brandId = try store.insertBrand(name: brandName, color: "#6366f1")
                projectId = try store.insertProject(brandId: brandId, name: projName, color: "#10b981")
            }

            // Create rules
            var ruleCount = 0
            for rule in req.rules ?? [] {
                guard let ruleType = RuleType(rawValue: rule.ruleType) else { continue }
                try store.insertRule(
                    projectId: projectId,
                    ruleType: ruleType,
                    pattern: rule.pattern,
                    isRegex: rule.isRegex ?? false
                )
                ruleCount += 1
            }

            // Reload rules and auto-assign
            projectMatcher.reloadRules()
            let assigned = projectMatcher.autoAssignUnclassified()

            return .ok("{\"projectId\":\(projectId),\"rulesCreated\":\(ruleCount),\"assigned\":\(assigned)}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    // MARK: - HTTP Response Builder

    private func buildHTTPResponse(_ response: APIResponse) -> String {
        let statusText: String
        switch response.status {
        case 200: statusText = "OK"
        case 201: statusText = "Created"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "OK"
        }

        let bodyData = response.body.data(using: .utf8) ?? Data()
        return [
            "HTTP/1.1 \(response.status) \(statusText)",
            "Content-Type: \(response.contentType)",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-cache, no-store, must-revalidate",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            response.body
        ].joined(separator: "\r\n")
    }

    // MARK: - Helpers

    private func jsonString(_ str: String) -> String {
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
