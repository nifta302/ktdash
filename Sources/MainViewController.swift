import UIKit
import WebKit

/// Окно с вашей страницей (Resources/main.html). Вместо запросов к Wi-Fi страница получает данные по Bluetooth.
final class MainViewController: UIViewController, WKScriptMessageHandler {
    private var web: WKWebView!
    private let ble = BleLink()

    // Подменяет fetch('/s') и fetch('/set?...') так, чтобы страница работала с платой через Bluetooth.
    private let shim = """
    (function(){
      var last=null,lastAt=0,waiters=[];
      window.KT={push:function(j){last=j;lastAt=Date.now();var w=waiters;waiters=[];w.forEach(function(f){f(j)})}};
      function nextState(ms){return new Promise(function(res){var done=false;
        function f(j){if(!done){done=true;res(j)}}
        waiters.push(f);setTimeout(function(){f(last||{})},ms)})}
      var orig=window.fetch;
      window.fetch=function(u){
        u=String(u);
        if(u.indexOf('/set?')===0){
          window.webkit.messageHandlers.kt.postMessage(u.split('?')[1]);
          return nextState(1200).then(function(j){return{json:function(){return Promise.resolve(j)}}});
        }
        if(u==='/s'){
          if(!last)return Promise.reject(new Error('no data'));
          var j=(Date.now()-lastAt<1000)?last:Object.assign({},last,{link:0});   // данные старше секунды считаются потерянными
          return Promise.resolve({json:function(){return Promise.resolve(j)}});
        }
        return orig.apply(this,arguments);
      };
    })();
    """

    override func loadView() {
        view = UIView()
        view.backgroundColor = .black
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.add(self, name: "kt")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc

        web = WKWebView(frame: .zero, configuration: cfg)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        ble.onLine = { [weak self] line in
            DispatchQueue.main.async {
                self?.web.evaluateJavaScript("window.KT&&KT.push(\(line))", completionHandler: nil)
            }
        }

        if let url = Bundle.main.url(forResource: "main", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            // baseURL с http: нужен, чтобы страница включила режим «на плате» (а не демо)
            web.loadHTMLString(html, baseURL: URL(string: "http://app.local/"))
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let cmd = message.body as? String { ble.write(cmd) }
    }

    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .landscape }
}
