// The daily check of the commission configurations (periods about to end, a first day without a configuration,
// the weekly digest) with the day passed in, and the launcher that the scheduled job runs.
@IsTest
private class CommissionDailyCheckTest {

    // Any day will do: the check is told which day it is
    private static final Date DAY = Date.newInstance(2031, 3, 12);

    private static User finance;
    private static User head;

    // The test catalog with its own notice days and digest weekday, and the people who are told
    private static void prepare(Decimal noticeDays, String weekday) {
        CommissionTestData.useCatalog();
        finance = CommissionTestData.finance();
        head = CommissionTestData.headOfSales();
        CommissionTestData.setSetting(new Map<String, Object>{
            'Expiry_Notice_Days__c' => noticeDays, 'Digest_Weekday__c' => weekday, 'Email_Enabled__c' => false
        });
        CommissionAccess.reset();
        CommissionNotifier.sentLog.clear();
    }

    private static List<CommissionNotifier.Sent> sent(String title) {
        List<CommissionNotifier.Sent> found = new List<CommissionNotifier.Sent>();
        for (CommissionNotifier.Sent entry : CommissionNotifier.sentLog) {
            if (entry.title == title) {
                found.add(entry);
            }
        }
        return found;
    }

    // A weekday that is neither the one of the day nor of the day after
    private static String anotherWeekday(Date day) {
        return CommissionDailyCheck.weekdayOf(day.addDays(3));
    }

    @IsTest
    static void aPeriodAboutToEndWithoutASuccessorIsAnnounced() {
        prepare(7, anotherWeekday(DAY));
        Project__c project = CommissionTestData.project('Daily Ending');
        Commission_Config__c config = CommissionTestData.insertApproved(project.Id, DAY.addDays(-100), DAY.addDays(7));

        Test.startTest();
        CommissionDailyCheck.run(DAY);
        List<CommissionNotifier.Sent> ending = sent(Label.Commission_Notify_Ending_Title);
        System.assertEquals(1, ending.size(), 'One notification lists the configurations that end in seven days');
        System.assert(ending[0].body.contains('Daily Ending'), 'The project is named: ' + ending[0].body);
        System.assert(ending[0].body.contains(CommissionTargetService.formatDate(DAY.addDays(7))), 'With the last day: ' + ending[0].body);
        System.assert(ending[0].userIds.contains(finance.Id), 'Finance is told');
        System.assert(ending[0].userIds.contains(head.Id), 'The Head of Sales is told');
        System.assertEquals(config.Id, ending[0].configId, 'A single configuration is opened by the notification');
        System.assertEquals(0, sent(Label.Commission_Notify_Gap_Title).size(), 'The project is still covered today');
        System.assertEquals(0, sent(Label.Commission_Notify_Digest_Title).size(), 'It is not the day of the digest');

        // Only on the exact day
        CommissionNotifier.sentLog.clear();
        CommissionDailyCheck.run(DAY.addDays(1));
        System.assertEquals(0, sent(Label.Commission_Notify_Ending_Title).size(), 'Six days before the end nothing is repeated');

        // With an approved next period there is nothing to announce
        CommissionTestData.insertApproved(project.Id, DAY.addDays(8), DAY.addDays(200));
        CommissionDailyCheck.run(DAY);
        Test.stopTest();
        System.assertEquals(0, sent(Label.Commission_Notify_Ending_Title).size(), 'An approved successor keeps the check quiet');
    }

    @IsTest
    static void aBlankNoticeSwitchesTheEndingCheckOff() {
        prepare(null, null);
        Project__c project = CommissionTestData.project('Daily No Notice');
        CommissionTestData.insertApproved(project.Id, DAY.addDays(-100), DAY.addDays(7));

        Test.startTest();
        CommissionDailyCheck.run(DAY);
        System.assertEquals(0, CommissionNotifier.sentLog.size(), 'Without notice days nothing is announced');
        prepare(0, null);
        CommissionDailyCheck.run(DAY);
        Test.stopTest();
        System.assertEquals(0, CommissionNotifier.sentLog.size(), 'Zero notice days switch the check off as well');
    }

    @IsTest
    static void theFirstDayWithoutAConfigurationIsAnnounced() {
        prepare(7, anotherWeekday(DAY));
        Project__c project = CommissionTestData.project('Daily Gap');
        CommissionTestData.insertApproved(project.Id, DAY.addDays(-100), DAY.addDays(-1));
        // A project that never had a configuration is a matter for the digest, not for this check
        CommissionTestData.project('Daily Never');

        Test.startTest();
        CommissionDailyCheck.run(DAY);
        List<CommissionNotifier.Sent> gaps = sent(Label.Commission_Notify_Gap_Title);
        System.assertEquals(1, gaps.size(), 'The first uncovered day is announced');
        System.assert(gaps[0].body.contains('Daily Gap'), 'The project is named: ' + gaps[0].body);
        System.assert(!gaps[0].body.contains('Daily Never'), 'A project that was not covered yesterday is not: ' + gaps[0].body);
        System.assert(gaps[0].userIds.contains(finance.Id), 'Finance is told');
        System.assertEquals(null, gaps[0].configId, 'It opens the overview');

        CommissionNotifier.sentLog.clear();
        CommissionDailyCheck.run(DAY.addDays(1));
        Test.stopTest();
        System.assertEquals(0, sent(Label.Commission_Notify_Gap_Title).size(), 'Only on the first day');
    }

    @IsTest
    static void theWeeklyDigestListsEveryProjectWithoutAConfiguration() {
        prepare(7, CommissionDailyCheck.weekdayOf(DAY).toUpperCase());
        CommissionTestData.project('Daily Digest Bare');
        Project__c covered = CommissionTestData.project('Daily Digest Covered');
        CommissionTestData.insertApproved(covered.Id, DAY.addDays(-10), DAY.addDays(100));

        Test.startTest();
        CommissionDailyCheck.run(DAY);
        List<CommissionNotifier.Sent> digests = sent(Label.Commission_Notify_Digest_Title);
        System.assertEquals(1, digests.size(), 'One digest on the weekday of the setting');
        System.assert(digests[0].body.contains('Daily Digest Bare'), 'The project without a configuration is listed: ' + digests[0].body);
        System.assert(!digests[0].body.contains('Daily Digest Covered'), 'A covered project is not: ' + digests[0].body);

        CommissionNotifier.sentLog.clear();
        CommissionDailyCheck.run(DAY.addDays(1));
        Test.stopTest();
        System.assertEquals(0, sent(Label.Commission_Notify_Digest_Title).size(), 'On the other days there is no digest');
    }

    @IsTest
    static void weekdaysAreNamedInEnglish() {
        System.assertEquals('Wednesday', CommissionDailyCheck.weekdayOf(Date.newInstance(2031, 3, 12)), 'A day after the known Sunday');
        System.assertEquals('Sunday', CommissionDailyCheck.weekdayOf(Date.newInstance(2023, 1, 1)), 'The known Sunday itself');
        System.assertEquals('Monday', CommissionDailyCheck.weekdayOf(Date.newInstance(2026, 10, 12)), 'The day of the digest in the Commission Setting');
        System.assertEquals('Saturday', CommissionDailyCheck.weekdayOf(Date.newInstance(2022, 12, 31)), 'A day before the known Sunday');
    }

    @IsTest
    static void theCheckIsStartedByItsName() {
        prepare(7, CommissionDailyCheck.weekdayOf(DAY));
        CommissionTestData.project('Daily Callable');

        Test.startTest();
        Object result = new CommissionDailyCheck().call('run', new Map<String, Object>{ 'today' => DAY });
        System.assertEquals(null, result, 'The check returns nothing');
        System.assertEquals(1, sent(Label.Commission_Notify_Digest_Title).size(), 'It ran for the day it was given');

        // Without a day it checks today
        new CommissionDailyCheck().call('run', null);
        Boolean refused = false;
        try {
            new CommissionDailyCheck().call('sweep', null);
        } catch (CommissionDailyCheck.CheckException problem) {
            refused = true;
        }
        Test.stopTest();
        System.assert(refused, 'An unknown action is refused');
    }

    @IsTest
    static void theLauncherStartsTheWorkerNamedInTheSetting() {
        prepare(7, CommissionDailyCheck.weekdayOf(Date.today()));
        CommissionTestData.project('Daily Launcher');

        Test.startTest();
        System.assertEquals(false, CommissionJobLauncher.launch(null), 'No worker name, nothing to start');
        System.assertEquals(false, CommissionJobLauncher.launch('Commission_No_Such_Worker'), 'A missing class does not fail the job');
        System.assertEquals(false, CommissionJobLauncher.launch('CommissionDto'), 'A class that cannot be called is not started');
        System.assertEquals(0, CommissionNotifier.sentLog.size(), 'Nothing ran so far');

        System.assertEquals(true, CommissionJobLauncher.launch('CommissionDailyCheck'), 'A valid worker is started');
        System.assertEquals(1, sent(Label.Commission_Notify_Digest_Title).size(), 'And did its work for today');

        // The scheduled entry reads the name from the setting
        CommissionNotifier.sentLog.clear();
        CommissionJobLauncher.workerOverride = 'Commission_No_Such_Worker';
        new CommissionJobLauncher().execute(null);
        System.assertEquals(0, CommissionNotifier.sentLog.size(), 'A wrong name in the setting starts nothing and raises no error');
        CommissionJobLauncher.workerOverride = 'CommissionDailyCheck';
        new CommissionJobLauncher().execute(null);
        System.assertEquals(1, sent(Label.Commission_Notify_Digest_Title).size(), 'The right name runs the check');

        // Without an override the name comes from the Commission Setting record of the org, when there is one
        CommissionJobLauncher.workerOverride = null;
        Commission_Setting__mdt stored = Commission_Setting__mdt.getInstance('Default');
        System.assertEquals(stored == null ? null : stored.Job_Worker_Class__c, CommissionJobLauncher.workerName(), 'The worker of the setting');
        String cron = '0 30 6 * * ?';
        Id jobId = System.schedule('Commission Daily Check (test)', cron, new CommissionJobLauncher());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'The launcher can be scheduled');
    }
}