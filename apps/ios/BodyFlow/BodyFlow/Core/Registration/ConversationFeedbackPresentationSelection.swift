import Foundation

/// Representation selection only. Neither the header nor decoder metadata is
/// authentication, current clinical permission, a receipt or a write grant.
/// No shipped runtime factory selects this dormant port.
enum ConversationFeedbackPresentationSelection: String, Sendable, Equatable {
  case v2 = "2"
  static let header = "X-Conversation-Feedback-Presentation"
  private static let key = CodingUserInfoKey(
    rawValue: "conversation.feedback.presentation.selection")!

  static func selected(from decoder: any Decoder) -> Self? {
    guard let raw = decoder.userInfo[key] as? String else { return nil }
    return Self(rawValue: raw)
  }
  static func decoder(selection: Self?) -> JSONDecoder {
    let decoder = JSONDecoder()
    if let selection { decoder.userInfo[key] = selection.rawValue }
    return decoder
  }
  /// Only a matching frozen request and exact response echo select wrapper2.
  static func negotiated(request: Self?, echo: String?) -> Self? {
    request == .v2 && echo == Self.v2.rawValue ? .v2 : nil
  }
}
