import UIKit
import WebKit

class ViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    var webView: WKWebView!
    var targetPhoneNumber = ""
    let phoneTextField = UITextField()
    let fetchButton = UIButton(type: .system)
    let loadingLabel = UILabel()
    let resultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupWebView()
    }

    func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "DataBridge")
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isHidden = true
        view.addSubview(webView)
    }

    @objc func fetchButtonClicked() {
        guard let phone = phoneTextField.text, !phone.isEmpty else { return }
        targetPhoneNumber = phone
        loadingLabel.text = "جار الاستعلام..."
        loadingLabel.isHidden = false
        resultLabel.isHidden = true
        fetchButton.isEnabled = false
        
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records, completionHandler: {
                let url = URL(string: "https://ptc.gov.ye/?page_id=9017")!
                self.webView.load(URLRequest(url: url))
            })
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString, url.contains("ptc.gov.ye") {
            let js = """
            javascript:(function() {
                var state = 0; var waitCounter = 0; var dynamicPhone = '\(targetPhoneNumber)';
                var timer = setInterval(function() {
                    var allTables = document.querySelectorAll('table');
                    for (var i = 0; i < allTables.length; i++) {
                        var tbl = allTables[i];
                        if(tbl.innerText.indexOf('رقم الهاتف') > -1 || tbl.innerText.indexOf('الرصيد') > -1) {
                            clearInterval(timer);
                            var dataObj = { pkg: '', outMins: '', internet: '', expiry: '' };
                            var currentSection = '';
                            var rows = tbl.querySelectorAll('tr');
                            rows.forEach(r => {
                                var tds = r.querySelectorAll('td, th');
                                if(tds.length === 1) currentSection = (tds[0].textContent || tds[0].innerText).trim();
                                else if(tds.length >= 2) {
                                    var key = (tds[0].textContent || tds[0].innerText).trim();
                                    var val = (tds[1].textContent || tds[1].innerText).trim();
                                    if(key.indexOf('الباقة') > -1) dataObj.pkg = val;
                                    else if(key.indexOf('تاريخ انتهاء') > -1) dataObj.expiry = val;
                                    else if(currentSection.indexOf('خارج الشبكة') > -1 && key.indexOf('المتاح') > -1) dataObj.outMins = val;
                                    else if(currentSection.indexOf('البيانات') > -1 && key.indexOf('المتاح') > -1) dataObj.internet = val;
                                }
                            });
                            window.webkit.messageHandlers.DataBridge.postMessage({type: 'result', data: dataObj});
                            return;
                        }
                    }
                    if (state === 3) {
                        var errorMsg = document.querySelector('.wpcf7-response-output, .wpcf7-validation-errors, .alert-danger, span.wpcf7-not-valid-tip');
                        if (errorMsg && errorMsg.innerText.trim() !== '') {
                            var txt = errorMsg.innerText.trim();
                            if(txt.indexOf('بنجاح') === -1) {
                                clearInterval(timer);
                                window.webkit.messageHandlers.DataBridge.postMessage({type: 'error', data: txt});
                                return;
                            }
                        }
                    }
                    if(state === 0) {
                        var phoneInputs = document.querySelectorAll('input'); var phone = null;
                        for(var i=0; i<phoneInputs.length; i++) {
                            var p = phoneInputs[i].placeholder || '';
                            if(p.indexOf('هاتف') > -1 || p.indexOf('رقم') > -1 || phoneInputs[i].name.indexOf('phone') > -1) { phone = phoneInputs[i]; break; }
                        }
                        var check = document.querySelector('input[type="checkbox"]');
                        if(phone && check) { phone.value = dynamicPhone; check.click(); state = 1; }
                    } else if(state === 1) {
                        waitCounter++; if(waitCounter >= 8) state = 2;
                    } else if(state === 2) {
                        var buttons = document.querySelectorAll('input[type="submit"], button'); var targetBtn = null;
                        for(var i=0; i<buttons.length; i++) {
                            var txt = (buttons[i].value || buttons[i].innerText || '').trim();
                            if(txt.indexOf('استعلام') > -1 && txt.indexOf('بحث') === -1) { targetBtn = buttons[i]; break; }
                        }
                        if(targetBtn && !targetBtn.disabled) { targetBtn.click(); state = 3; }
                    }
                }, 300);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "DataBridge", let dict = message.body as? [String: Any] {
            DispatchQueue.main.async {
                self.loadingLabel.isHidden = true
                self.fetchButton.isEnabled = true
                if let type = dict["type"] as? String {
                    if type == "result", let data = dict["data"] as? [String: String] {
                        let pkg = data["pkg"] ?? "--"
                        let internet = data["internet"] ?? "--"
                        let expiry = data["expiry"] ?? "--"
                        self.resultLabel.text = "الباقة: \(pkg)\nالبيانات: \(internet)\nالانتهاء: \(expiry)"
                        self.resultLabel.textColor = .systemGreen
                        self.resultLabel.isHidden = false
                    } else if type == "error", let errorMsg = dict["data"] as? String {
                        self.loadingLabel.text = errorMsg
                        self.loadingLabel.textColor = .systemRed
                        self.loadingLabel.isHidden = false
                    }
                }
            }
        }
    }

    func setupUI() {
        view.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        phoneTextField.placeholder = "رقم يمن فورجي المستهدف"
        phoneTextField.text = "101121978"
        phoneTextField.borderStyle = .roundedRect
        phoneTextField.textAlignment = .center
        phoneTextField.keyboardType = .phonePad
        phoneTextField.frame = CGRect(x: 20, y: 100, width: view.bounds.width - 40, height: 50)
        view.addSubview(phoneTextField)
        
        fetchButton.setTitle("استعلام", for: .normal)
        fetchButton.backgroundColor = .systemBlue
        fetchButton.setTitleColor(.white, for: .normal)
        fetchButton.layer.cornerRadius = 12
        fetchButton.frame = CGRect(x: 20, y: 170, width: view.bounds.width - 40, height: 50)
        fetchButton.addTarget(self, action: #selector(fetchButtonClicked), for: .touchUpInside)
        view.addSubview(fetchButton)
        
        loadingLabel.frame = CGRect(x: 20, y: 240, width: view.bounds.width - 40, height: 30)
        loadingLabel.textAlignment = .center
        loadingLabel.textColor = .systemBlue
        loadingLabel.isHidden = true
        view.addSubview(loadingLabel)
        
        resultLabel.frame = CGRect(x: 20, y: 280, width: view.bounds.width - 40, height: 150)
        resultLabel.numberOfLines = 0
        resultLabel.textAlignment = .right
        resultLabel.isHidden = true
        view.addSubview(resultLabel)
    }
}