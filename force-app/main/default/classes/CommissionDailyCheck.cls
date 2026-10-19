// The daily look at the commission configurations, started by CommissionJobLauncher through its name in the
// Commission Setting (so the scheduled job holds no reference to this class).
// It only tells people; it never changes a configuration. Three checks, one notification each:
// (a) configurations that end in N days (Expiry Notice Days) with no approved next period,
// (b) projects whose first day without an approved configuration is today,
// (c) once a week (Digest Weekday): every active project without an approved configuration.
public without sharing class CommissionDailyCheck implements Callable {
    // Messages this class shows or sends
    @TestVisible private static final String COMMISSION_NOTIFY_DIGEST_BODY = '{0} active projects have no approved commission configuration today: {1}';
    @TestVisible private static final String COMMISSION_NOTIFY_DIGEST_TITLE = 'Projects without a commission configuration';
    @TestVisible private static final String COMMISSION_NOTIFY_ENDING_BODY = 'These commission configurations end in {0} days and no next period is approved: {1}';
    @TestVisible private static final String COMMISSION_NOTIFY_ENDING_LINE = '{0} ({1}, ends {2})';
    @TestVisible private static final String COMMISSION_NOTIFY_ENDING_TITLE = 'Commission configuration ending soon';
    @TestVisible private static final String COMMISSION_NOTIFY_GAP_BODY = 'From today these projects have no approved commission configuration: {0}';
    @TestVisible private static final String COMMISSION_NOTIFY_GAP_TITLE = 'Project without a commission configuration';


    private static final String STATUS_APPROVED = 'Approved';
    private static final String ACTION_RUN = 'run';
    // Optional argument of call('run', ...): the day to check instead of today
    private static final String ARGUMENT_TODAY = 'today';
    // The values Digest Weekday can have, counted from a day that was a Sunday
    private static final List<String> WEEKDAYS = new List<String>{
        'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
    };
    private static final Date KNOWN_SUNDAY = Date.newInstance(2023, 1, 1);

    public class CheckException extends Exception {}

    public Object call(String action, Map<String, Object> arguments) {
        if (action != ACTION_RUN) {
            throw new CheckException('Unknown action: ' + action);
        }
        Object day = arguments == null ? null : arguments.get(ARGUMENT_TODAY);
        run(day instanceof Date ? (Date) day : Date.today());
        return null;
    }

    public static void run(Date today) {
        Date day = today == null ? Date.today() : today;
        Date yesterday = day.addDays(-1);
        Commission_Setting__mdt setting = CommissionCatalog.setting();
        Integer notice = setting.Expiry_Notice_Days__c == null ? 0 : setting.Expiry_Notice_Days__c.intValue();

        // Finance, the people who watch the configurations and the people who keep the targets
        Set<Id> audience = new Set<Id>();
        for (String capability : new List<String>{ CommissionAccess.CONFIGURE, CommissionAccess.ALERT, CommissionAccess.TARGETS }) {
            for (User person : CommissionAccess.usersWho(capability)) {
                audience.add(person.Id);
            }
        }
        if (audience.isEmpty()) {
            return;
        }

        // The approved configurations of the active projects that were still running yesterday or start later
        Map<Id, List<Commission_Config__c>> byProject = new Map<Id, List<Commission_Config__c>>();
        for (Commission_Config__c config : [
            SELECT Id, Name, Project__c, Project__r.Name, Start_Date__c, End_Date__c
            FROM Commission_Config__c
            WHERE Status__c = :STATUS_APPROVED AND Project__r.Active__c = true
                AND Start_Date__c != null AND End_Date__c >= :yesterday
            WITH SYSTEM_MODE
            ORDER BY Project__r.Name, Start_Date__c
        ]) {
            if (!byProject.containsKey(config.Project__c)) {
                byProject.put(config.Project__c, new List<Commission_Config__c>());
            }
            byProject.get(config.Project__c).add(config);
        }
        List<Project__c> projects = [SELECT Id, Name FROM Project__c WHERE Active__c = true WITH SYSTEM_MODE ORDER BY Name];

        // One check that fails does not stop the others
        try {
            if (notice > 0) {
                ending(byProject, day.addDays(notice), notice, audience);
            }
        } catch (Exception problem) {
            note('ending', problem);
        }
        try {
            gaps(projects, byProject, day, yesterday, audience);
        } catch (Exception problem) {
            note('gaps', problem);
        }
        try {
            digest(projects, byProject, day, setting.Digest_Weekday__c, audience);
        } catch (Exception problem) {
            note('digest', problem);
        }
    }

    // (a) Ends on the notice day and nothing approved starts the day after
    private static void ending(Map<Id, List<Commission_Config__c>> byProject, Date lastDay, Integer notice, Set<Id> audience) {
        List<String> lines = new List<String>();
        List<Id> configIds = new List<Id>();
        for (List<Commission_Config__c> configs : byProject.values()) {
            for (Commission_Config__c config : configs) {
                if (config.End_Date__c != lastDay) {
                    continue;
                }
                Boolean followed = false;
                for (Commission_Config__c other : configs) {
                    if (other.Id != config.Id && other.Start_Date__c == lastDay.addDays(1)) {
                        followed = true;
                        break;
                    }
                }
                if (!followed) {
                    lines.add(CommissionTargetService.fill(COMMISSION_NOTIFY_ENDING_LINE, new List<Object>{
                        config.Project__r == null ? '' : config.Project__r.Name, config.Name, CommissionTargetService.formatDate(config.End_Date__c)
                    }));
                    configIds.add(config.Id);
                }
            }
        }
        if (lines.isEmpty()) {
            return;
        }
        // With one configuration the notification opens it, with several the overview
        CommissionNotifier.send(audience, COMMISSION_NOTIFY_ENDING_TITLE,
            CommissionTargetService.fill(COMMISSION_NOTIFY_ENDING_BODY, new List<Object>{ notice, String.join(lines, '; ') }),
            configIds.size() == 1 ? configIds[0] : null);
    }

    // (b) Covered yesterday, not covered today: the first day without a configuration
    private static void gaps(List<Project__c> projects, Map<Id, List<Commission_Config__c>> byProject, Date day, Date yesterday, Set<Id> audience) {
        List<String> names = new List<String>();
        for (Project__c project : projects) {
            if (!covered(byProject.get(project.Id), day) && covered(byProject.get(project.Id), yesterday)) {
                names.add(project.Name);
            }
        }
        if (names.isEmpty()) {
            return;
        }
        CommissionNotifier.send(audience, COMMISSION_NOTIFY_GAP_TITLE,
            CommissionTargetService.fill(COMMISSION_NOTIFY_GAP_BODY, new List<Object>{ String.join(names, '; ') }), null);
    }

    // (c) On the weekday of the setting: every active project that has no approved configuration today
    private static void digest(List<Project__c> projects, Map<Id, List<Commission_Config__c>> byProject, Date day, String weekday, Set<Id> audience) {
        if (String.isBlank(weekday) || weekdayOf(day) != weekday.trim()) {
            return;
        }
        List<String> names = new List<String>();
        for (Project__c project : projects) {
            if (!covered(byProject.get(project.Id), day)) {
                names.add(project.Name);
            }
        }
        if (names.isEmpty()) {
            return;
        }
        CommissionNotifier.send(audience, COMMISSION_NOTIFY_DIGEST_TITLE,
            CommissionTargetService.fill(COMMISSION_NOTIFY_DIGEST_BODY, new List<Object>{ names.size(), String.join(names, '; ') }), null);
    }

    private static Boolean covered(List<Commission_Config__c> configs, Date day) {
        if (configs != null) {
            for (Commission_Config__c config : configs) {
                if (config.Start_Date__c <= day && config.End_Date__c >= day) {
                    return true;
                }
            }
        }
        return false;
    }

    // Monday, Tuesday ... always in English, as the Commission Setting names the day, whatever the language of
    // the user the job runs as
    @TestVisible
    private static String weekdayOf(Date day) {
        Integer position = Math.mod(Math.mod(KNOWN_SUNDAY.daysBetween(day), 7) + 7, 7);
        return WEEKDAYS[position];
    }

    private static void note(String what, Exception problem) {
        System.debug(LoggingLevel.ERROR, '>>> [Commission] Daily check failed (' + what + '): ' + problem.getMessage() + ' ' + problem.getStackTraceString());
    }
}