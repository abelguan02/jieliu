import AppKit
import TrayCore

enum OnboardingChecks {
    static func run(root:URL) {
        let suite="app.jieliu.onboarding-check."+UUID().uuidString
        let preferences=UserDefaults(suiteName:suite)!
        defer { preferences.removePersistentDomain(forName:suite) }
        let model=AppModel(demo:true,preferences:preferences)
        var starts=0
        model.onRestart={ starts += 1 }
        let destination=root.appendingPathComponent("onboarding-archive")
        model.setDestination(destination)
        precondition(starts == 0 && !preferences.bool(forKey:"onboarded"),"Changing the onboarding folder must not start collection")
        precondition(model.destination == destination && preferences.string(forKey:"destination") == destination.path)
        let flow=OnboardingFlow(page:2,baseline:nil)
        flow.beginTrial(model)
        precondition(starts == 1 && preferences.bool(forKey:"onboarded"),"Start collecting must start the watcher")
        precondition(flow.page == 3 && flow.baseline == model.history.total,"Start must enter the trial with a fresh capture baseline")
        model.setDestination(destination)
        precondition(starts == 2,"Reselecting the same folder after starting must retry collection")
        model.lastError="History save failure"
        model.captureError="Archive unavailable"
        precondition(model.errorMessage == "Archive unavailable","Settings must surface the current capture failure")
        flow.returnToSetup()
        precondition(flow.page == 2 && preferences.bool(forKey:"onboarded"),"Returning to setup must preserve the explicit start decision")
        model.onRestart={ starts += 1; model.captureError="Still unavailable" }
        flow.beginTrial(model)
        precondition(starts == 3 && flow.page == 3 && model.captureError == "Still unavailable","Retry must preserve a new failure reported by the restarted watcher")
        model.onRestart={ starts += 1 }
        flow.returnToSetup(); flow.beginTrial(model)
        precondition(starts == 4 && model.captureError.isEmpty && model.lastError == "History save failure","Retry must clear only the previous capture error")
        model.captureError="Incomplete image"
        model.receive(Capture(url:destination.appendingPathComponent("recovered.png"),width:640,height:400))
        precondition(model.captureError.isEmpty && model.errorMessage == "History save failure","A recovered capture must clear its error without hiding unrelated errors")
        precondition(model.history.total > flow.baseline!,"The recovered capture must complete the trial")
        flow.beginTrial(model)
        precondition(model.history.total == flow.baseline,"Reopening the trial must wait for a new capture")
        print("PASS: onboarding explicit start, same-folder retry, failure/back/retry/recovery and unrelated error preservation")
    }
}
