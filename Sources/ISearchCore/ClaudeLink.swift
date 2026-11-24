import Foundation

/// Links that hand a prompt over to Claude.
public enum ClaudeLink {
    /// The Claude desktop app cuts prompts at this length (14,336 characters), so a longer one would be silently shortened anyway.
    public static let maxPromptLength = 14_336

    /// A normal chat in the Claude desktop app.
    public static func chat(prompt: String) -> URL {
        link(base: "claude://claude.ai/new?surface=chat", prompt: prompt)
    }

    /// The same chat on the web, for when the desktop app is not installed.
    public static func webChat(prompt: String) -> URL {
        link(base: "https://claude.ai/new", prompt: prompt)
    }

    /// An incognito chat. This has to go through the web: the desktop app's link handler drops every parameter it does not know, `incognito` included.
    public static func incognitoChat(prompt: String) -> URL {
        link(base: "https://claude.ai/new?incognito", prompt: prompt)
    }

    /// A new Claude Code session working in `folder`.
    public static func codeSession(folder: String, prompt: String = "") -> URL {
        link(base: "claude://code/new?folder=\(encode(folder))", prompt: prompt)
    }

    private static func link(base: String, prompt: String) -> URL {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = base
        if !trimmed.isEmpty {
            text += (base.contains("?") ? "&" : "?") + "q=" + encode(String(trimmed.prefix(maxPromptLength)))
        }
        guard let url = URL(string: text) else {
            preconditionFailure("A fully percent-encoded link must parse: \(text)")
        }
        return url
    }

    /// Stricter than `URLQueryItem`, which leaves `+` alone: the receiving side would read it as a space and turn "2+2" into "2 2".
    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-._~")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else {
            preconditionFailure("A Swift String is always valid Unicode, so percent-encoding it cannot fail")
        }
        return encoded
    }
}
