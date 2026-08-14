import Foundation

public struct SandboxCredentials: Sendable, Equatable {
    public var vercelToken: String?
    public var vercelTeam: String?
    public var vercelProject: String?
    public var e2bKey: String?
    public var modalToken: String?

    public init(
        vercelToken: String? = nil,
        vercelTeam: String? = nil,
        vercelProject: String? = nil,
        e2bKey: String? = nil,
        modalToken: String? = nil
    ) {
        self.vercelToken = vercelToken
        self.vercelTeam = vercelTeam
        self.vercelProject = vercelProject
        self.e2bKey = e2bKey
        self.modalToken = modalToken
    }

    public static let empty = SandboxCredentials()
}

/// Pure map from the user's computer choice to local jail vs a cloud create spec.
public struct ComputerRoute: Sendable, Equatable {
    public var choice: ComputerChoice
    public var spec: HTTPSandboxSpec?

    public init(choice: ComputerChoice, spec: HTTPSandboxSpec?) {
        self.choice = choice
        self.spec = spec
    }

    public var isLocal: Bool { spec == nil && choice == .local }
}

public enum ComputerRouter: Sendable {
    public static func route(
        _ choice: ComputerChoice,
        credentials: SandboxCredentials
    ) -> ComputerRoute {
        switch choice {
        case .local:
            return ComputerRoute(choice: .local, spec: nil)
        case .vercel:
            return ComputerRoute(
                choice: .vercel,
                spec: VercelProvider(
                    token: credentials.vercelToken ?? "",
                    teamID: credentials.vercelTeam ?? "",
                    projectID: credentials.vercelProject ?? "",
                    client: HTTPSandboxClient(session: RecordingHTTPSession())
                ).createSpec()
            )
        case .e2b:
            return ComputerRoute(
                choice: .e2b,
                spec: E2BProvider(
                    apiKey: credentials.e2bKey ?? "",
                    client: HTTPSandboxClient(session: RecordingHTTPSession())
                ).createSpec()
            )
        case .modal:
            return ComputerRoute(
                choice: .modal,
                spec: ModalProvider(
                    token: credentials.modalToken ?? "",
                    client: HTTPSandboxClient(session: RecordingHTTPSession())
                ).createSpec()
            )
        }
    }

    public static func computer(
        _ choice: ComputerChoice,
        workspace: URL,
        extraRoots: [URL] = [],
        credentials: SandboxCredentials,
        session: (any HTTPSandboxSessioning)? = nil
    ) throws -> any SandboxProviding {
        switch choice {
        case .local:
            return LocalComputer(workspace: workspace, extraRoots: extraRoots)
        case .vercel:
            let token = credentials.vercelToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !token.isEmpty else {
                throw JoyflowStoreError.io("Add a Vercel token in Settings to use a cloud computer.")
            }
            return VercelProvider(
                token: token,
                teamID: credentials.vercelTeam ?? "",
                projectID: credentials.vercelProject ?? "",
                client: HTTPSandboxClient(session: session ?? URLSessionSandbox())
            )
        case .e2b:
            let key = credentials.e2bKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else {
                throw JoyflowStoreError.io("Add an E2B key in Settings to use a cloud computer.")
            }
            return E2BProvider(
                apiKey: key,
                client: HTTPSandboxClient(session: session ?? URLSessionSandbox())
            )
        case .modal:
            let token = credentials.modalToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !token.isEmpty else {
                throw JoyflowStoreError.io("Add a Modal token in Settings to use a cloud computer.")
            }
            return ModalProvider(
                token: token,
                client: HTTPSandboxClient(session: session ?? URLSessionSandbox())
            )
        }
    }
}

public struct URLSessionSandbox: HTTPSandboxSessioning {
    public init() {}

    public func perform(_ spec: HTTPSandboxSpec) async throws -> (Int, Data) {
        guard let url = URL(string: spec.createURL) else {
            throw JoyflowStoreError.invalidURL(spec.createURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = spec.method
        spec.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = Data(spec.body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JoyflowStoreError.io("sandbox \(status): \(body)")
        }
        return (status, data)
    }
}
