import Foundation

extension Notification.Name {
    /// Posted when the user taps "Done" after a successful export, to collapse the navigation
    /// stack back to HomeView regardless of how deep it is (Recording Studio -> Editor, or
    /// Projects -> Editor). The app still uses the old `NavigationView`/`NavigationLink(isActive:)`
    /// style throughout, which has no built-in "pop to root" -- HomeView listens for this and
    /// resets its own push state, which tears down everything pushed on top of it.
    static let returnToHome = Notification.Name("reactcam.returnToHome")
}
