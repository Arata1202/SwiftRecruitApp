import SwiftUI
import UIKit

/// The empty page has no rows. Keep its viewport sizing out of List's self-sizing
/// cell and refresh-inset updates; UIKit owns only scrolling and refresh here.
struct HomeEmptyRefreshView<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let reload: @MainActor () async -> Void

    init(reload: @escaping @MainActor () async -> Void, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.reload = reload
    }

    func makeUIViewController(context: Context) -> HomeEmptyRefreshController {
        HomeEmptyRefreshController(content: AnyView(content.environment(\.self, context.environment)), reload: reload)
    }

    func updateUIViewController(_ controller: HomeEmptyRefreshController, context: Context) {
        controller.host.rootView = AnyView(content.environment(\.self, context.environment))
        controller.reload = reload
    }

    static func dismantleUIViewController(_ controller: HomeEmptyRefreshController, coordinator: ()) {
        controller.cancelRefresh()
    }
}

@MainActor
final class HomeEmptyRefreshController: UIViewController {
    let scrollView = UIScrollView()
    let refreshControl = UIRefreshControl()
    let host: UIHostingController<AnyView>
    var reload: @MainActor () async -> Void
    private(set) var refreshTask: Task<Void, Never>?

    init(content: AnyView, reload: @escaping @MainActor () async -> Void) {
        host = UIHostingController(rootView: content)
        self.reload = reload
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = scrollView
        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        scrollView.refreshControl = refreshControl
        refreshControl.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .valueChanged)
        addChild(host)
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            host.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            host.view.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        host.didMove(toParent: self)
    }

    func refresh() {
        guard refreshTask == nil else { return }
        let reload = reload
        refreshTask = Task { [weak self] in
            await reload()
            guard !Task.isCancelled else { return }
            self?.refreshControl.endRefreshing()
            self?.refreshTask = nil
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshControl.endRefreshing()
    }
}
