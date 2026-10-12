// The scheduled entry of the commission jobs ("Commission Daily Check", every morning).
// It only knows the name of the class that does the work, read from the Commission Setting (Job Worker Class),
// and starts it through Type.forName and System.Callable. Because nothing here refers to another Commission
// class, the scheduled job never blocks a later deploy of the module.
public without sharing class CommissionJobLauncher implements Schedulable {

    private static final String SETTING_NAME = 'Default';
    private static final String ACTION_RUN = 'run';

    // Tests name their own worker
    @TestVisible
    private static String workerOverride;

    public void execute(SchedulableContext context) {
        launch(workerName());
    }

    @TestVisible
    private static String workerName() {
        if (workerOverride != null) {
            return workerOverride;
        }
        Commission_Setting__mdt setting = Commission_Setting__mdt.getInstance(SETTING_NAME);
        return setting == null ? null : setting.Job_Worker_Class__c;
    }

    // True when the worker ran. A missing or broken worker is written to the log; the job itself never fails,
    // so it stays scheduled.
    @TestVisible
    private static Boolean launch(String name) {
        try {
            if (String.isBlank(name)) {
                System.debug(LoggingLevel.ERROR, '>>> [Commission] No job worker class is named in the Commission Setting.');
                return false;
            }
            Type workerType = Type.forName(name.trim());
            if (workerType == null) {
                System.debug(LoggingLevel.ERROR, '>>> [Commission] Job worker class not found: ' + name);
                return false;
            }
            Object worker = workerType.newInstance();
            if (!(worker instanceof Callable)) {
                System.debug(LoggingLevel.ERROR, '>>> [Commission] Job worker class is not Callable: ' + name);
                return false;
            }
            ((Callable) worker).call(ACTION_RUN, new Map<String, Object>());
            return true;
        } catch (Exception problem) {
            System.debug(LoggingLevel.ERROR, '>>> [Commission] Job worker failed: ' + problem.getMessage() + ' ' + problem.getStackTraceString());
            return false;
        }
    }
}