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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, !data.isEmpty else {
                connection.cancel()
                return
            }

            // Check if we have the full body based on Content-Length
            if let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = data[data.startIndex..<headerEnd.lowerBound]
                if let headerStr = String(data: headerData, encoding: .utf8)?.lowercased(),
                   let clRange = headerStr.range(of: "content-length: ") {
                    let afterCL = headerStr[clRange.upperBound...]
                    let clLine = afterCL.prefix(while: { $0 != "\r" && $0 != "\n" })
                    if let expectedLength = Int(clLine) {
                        let bodyStart = headerEnd.upperBound
                        let receivedBodyLength = data.count - data.distance(from: data.startIndex, to: bodyStart)
                        if receivedBodyLength < expectedLength {
                            // Need more data — read the rest
                            let remaining = expectedLength - receivedBodyLength
                            connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { moreContent, _, _, _ in
                                var fullData = data
                                if let more = moreContent { fullData.append(more) }
                                self.processRequest(fullData, connection: connection)
                            }
                            return
                        }
                    }
                }
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

        static func ok(_ json: String) -> APIResponse { APIResponse(status: 200, body: json) }
        static func created(_ json: String) -> APIResponse { APIResponse(status: 201, body: json) }
        static func badRequest(_ msg: String) -> APIResponse { APIResponse(status: 400, body: "{\"error\":\"\(msg)\"}") }
        static func notFound() -> APIResponse { APIResponse(status: 404, body: "{\"error\":\"not found\"}") }
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

        // Extract JSON body
        let body: String
        if let bodyStart = raw.range(of: "\r\n\r\n") {
            body = String(raw[bodyStart.upperBound...])
        } else {
            body = ""
        }

        switch (method, path) {
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
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct ClassifyRequest: Decodable {
            let activityIds: [Int64]
            let projectId: Int64
            let createRule: Bool?
            let ruleType: String?
            let rulePattern: String?
        }

        guard let req = try? JSONDecoder().decode(ClassifyRequest.self, from: data) else {
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
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct CreateProjectRequest: Decodable {
            let brandId: Int64
            let name: String
            let color: String?
        }

        guard let req = try? JSONDecoder().decode(CreateProjectRequest.self, from: data) else {
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
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct Req: Decodable { let id: Int64; let name: String?; let color: String? }
        guard let req = try? JSONDecoder().decode(Req.self, from: data) else {
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
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct Req: Decodable { let id: Int64 }
        guard let req = try? JSONDecoder().decode(Req.self, from: data) else {
            return .badRequest("invalid JSON")
        }
        do {
            try store.deleteBrand(id: req.id)
            projectMatcher.reloadRules()
            return .ok("{\"ok\":true}")
        } catch {
            return .badRequest(error.localizedDescription)
        }
    }

    private func handleUpdateProject(body: String) -> APIResponse {
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct Req: Decodable { let id: Int64; let name: String?; let color: String?; let brandId: Int64? }
        guard let req = try? JSONDecoder().decode(Req.self, from: data) else {
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
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct Req: Decodable { let id: Int64 }
        guard let req = try? JSONDecoder().decode(Req.self, from: data) else {
            return .badRequest("invalid JSON")
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
        guard let data = body.data(using: .utf8) else { return .badRequest("invalid body") }
        struct Req: Decodable { let id: Int64 }
        guard let req = try? JSONDecoder().decode(Req.self, from: data) else {
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
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(bodyData.count)",
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
