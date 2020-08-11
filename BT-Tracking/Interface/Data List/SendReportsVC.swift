//
//  SendReportsVC.swift
//  BT-Tracking
//
//  Created by Lukáš Foldýna on 11/08/2020.
//  Copyright © 2020 Covid19CZ. All rights reserved.
//

import UIKit
import Reachability
import RxSwift
import RxRelay
import DeviceKit

final class SendReportsVC: UIViewController {

    // MARK: -

    private let viewModel = SendReportsVM()

    private var code = BehaviorRelay<String>(value: "")
    private var isValid: Observable<Bool> {
        code.asObservable().map { phoneNumber -> Bool in
            InputValidation.code.validate(phoneNumber)
        }
    }
    private var keyboardHandler: KeyboardHandler!
    private var disposeBag = DisposeBag()

    private var expirationSeconds: TimeInterval = 0
    private var expirationTimer: Timer?

    private var firstAppear: Bool = true

    // MARK: - Outlets

    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var headlineLabel: UILabel!
    @IBOutlet private weak var bodyLabel: UILabel!
    @IBOutlet private weak var codeTextField: UITextField!

    @IBOutlet private weak var buttonsView: ButtonsBackgroundView!
    @IBOutlet private weak var buttonsBottomConstraint: NSLayoutConstraint!
    @IBOutlet private weak var actionButton: Button!

    override func viewDidLoad() {

        buttonsView.connect(with: scrollView)
        buttonsBottomConstraint.constant = ButtonsBackgroundView.BottomMargin

        setupTextField()
        setupStrings()

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if firstAppear {
            keyboardHandler.setup()
            codeTextField.becomeFirstResponder()
            firstAppear = false
        }
    }

    // MARK: - Actions

    @IBAction private func sendReportsAction() {
        guard let connection = try? Reachability().connection, connection != .unavailable else {
            showSendDataError()
            return
        }
        view.endEditing(true)
        verifyCode(code.value)
    }

    @IBAction private func resultAction() {
        performSegue(withIdentifier: "result", sender: nil)
    }

    @IBAction private func closeAction() {
        dismiss(animated: true)
    }
    
}


extension SendReportsVC: UITextFieldDelegate {

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let type: InputValidation
        if textField == codeTextField {
            type = .code
        } else {
            return true
        }

        return validateTextChange(with: type, textField: textField, changeCharactersIn: range, newString: string)
    }

}

private extension SendReportsVC {

    // MARK: - Setup

    func setupTextField() {
        keyboardHandler = KeyboardHandler(in: view, scrollView: scrollView, buttonsView: buttonsView, buttonsBottomConstraint: buttonsBottomConstraint)

        codeTextField.rx.text.orEmpty.bind(to: code).disposed(by: disposeBag)

        isValid.bind(to: actionButton.rx.isEnabled).disposed(by: disposeBag)
    }

    func setupStrings() {
        title = "Odeslat Data"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction))
    }

    // MARK: - Progress

    func reportShowProgress() {
        showProgress()

        isModalInPresentation = false
        navigationItem.setRightBarButton(nil, animated: true)
    }

    func reportHideProgress() {
        hideProgress()

        //isModalInPresentation = true
        navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction)), animated: true)
    }

    // MARK: - Reports

    enum ReportType {
        case normal, test
    }

    func verifyCode(_ code: String) {
        reportShowProgress()

        AppDelegate.dependency.verification.verify(with: code) { [weak self] result in
            switch result {
            case .success(let token):
                self?.askForTypeOfKeys(token: token)
            case .failure(let error):
                log("DataListVC: Failed to verify code \(error)")
                self?.reportHideProgress()
                self?.showVerifyError()
            }
        }
    }

    func askForTypeOfKeys(token: String) {
        let controller = UIAlertController(title: "Který druh klíčů?", message: nil, preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: "Test Keys", style: .default, handler: { [weak self] _ in
            self?.sendReport(with: .test, token: token)
        }))
        controller.addAction(UIAlertAction(title: "Normal Keys", style: .default, handler: {[weak self]  _ in
            self?.sendReport(with: .normal, token: token)
        }))
        controller.addAction(UIAlertAction(title: NSLocalizedString("active_background_mode_cancel", comment: ""), style: .cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }

    func sendReport(with type: ReportType, token: String) {
        let verificationService = AppDelegate.dependency.verification
        let reportService = AppDelegate.dependency.reporter
        let exposureService = AppDelegate.dependency.exposureService
        let callback: ExposureServicing.KeysCallback = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let keys):
                guard !keys.isEmpty else {
                    self.reportHideProgress()
                    self.showAlert(title: "Nemáte žádné klíče k odeslání, zkuste to později.", message: "")
                    return
                }

                do {
                    let secret = Data.random(count: 32)
                    let hmacKey = try reportService.calculateHmacKey(keys: keys, secret: secret)
                    verificationService.requestCertificate(token: token, hmacKey: hmacKey) { result in
                        switch result {
                        case .success(let certificate):
                            self.uploadKeys(keys: keys, verificationPayload: certificate, hmacSecret: secret)
                        case .failure(let error):
                            log("DataListVC: Failed to get verification payload \(error)")
                            self.reportHideProgress()
                            self.showSendDataError()
                        }
                    }
                } catch {
                    log("DataListVC: Failed to get hmac for keys \(error)")
                    self.reportHideProgress()
                    self.showSendDataError()
                }
            case .failure(let error):
                log("DataListVC: Failed to get exposure keys \(error)")
                self.reportHideProgress()
                self.showSendDataError()
            }
        }

        switch type {
        case .test:
            exposureService.getTestDiagnosisKeys(callback: callback)
        case .normal:
            exposureService.getDiagnosisKeys(callback: callback)
        }
    }

    func uploadKeys(keys: [ExposureDiagnosisKey], verificationPayload: String, hmacSecret: Data) {
        AppDelegate.dependency.reporter.uploadKeys(keys: keys, verificationPayload: verificationPayload, hmacSecret: hmacSecret, callback: { [weak self] result in
            self?.reportHideProgress()
            switch result {
            case .success:
                self?.resultAction()
            case .failure:
                self?.showSendDataError()
            }
        })
    }

    func showDownloadDataErrorFailed(_ error: Error) {
        show(error: error)
    }

    func showVerifyError() {
        showAlert(
            title: "Neplatný ověřovací kód",
            message: "Požádejte pracovníka hygienické stanice o zaslání nové SMS zprávy s ověřovacím kódem.",
            okHandler: { [weak self] in
                self?.codeTextField.text = nil
                self?.codeTextField.becomeFirstResponder()
            }
        )
    }

    func showSendDataError() {
        showAlert(
            title: viewModel.sendDataErrorFailedTitle,
            message: viewModel.sendDataErrorFailedMessage
        )
    }

}
