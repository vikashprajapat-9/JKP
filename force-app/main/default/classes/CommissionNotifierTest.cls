// Notifications of Commission Setup: who is told about a submission, an approval, a rejection, a withdrawal and a
// target change, and that nothing in the notifier lets an error out.
@IsTest
private class CommissionNotifierTest {

    private static final String ADVISOR = 'Sales_Advisor';

    private class Scene {
        Project__c project;
        Commission_Config__c config;
        User finance;
        User approver;
        User advisor;
        User manager;
    }

    // An approved configuration with a submitter, an approver and a decision on it
    private static Scene prepare(String projectName) {
        CommissionTestData.useCatalog();
        Scene setup = new Scene();
        setup.finance = CommissionTestData.finance();
        setup.approver = CommissionTestData.approver();
        setup.manager = CommissionTestData.seniorManager();
        setup.advisor = CommissionTestData.advisor();
        setup.project = CommissionTestData.project(projectName);
        Id configId = CommissionTestData.insertApproved(setup.project.Id, Date.today().addDays(-30), Date.today().addDays(300)).Id;
        Commission_Config__c config = [SELECT Id, Name, Reference__c FROM Commission_Config__c WHERE Id = :configId];
        config.Approver__c = setup.approver.Id;
        config.Submitted_By__c = setup.finance.Id;
        config.Approved_By__c = setup.approver.Id;
        config.Decision_By__c = setup.approver.Id;
        config.Decision_Comments__c = 'The Exceed rate is too high';
        if (String.isBlank(config.Reference__c)) {
            config.Reference__c = config.Name;
        }
        Boolean earlier = CommissionTriggerHandler.bypass;
        CommissionTriggerHandler.bypass = true;
        try {
            update config;
        } finally {
            CommissionTriggerHandler.bypass = earlier;
        }
        setup.config = [
            SELECT Id, Name, Reference__c, Version__c, Project__c, Start_Date__c, End_Date__c
            FROM Commission_Config__c WHERE Id = :configId
        ];
        CommissionAccess.reset();
        CommissionNotifier.sentLog.clear();
        return setup;
    }

    // The setting of the test catalog with emails switched on or off
    private static void useEmails(Boolean enabled) {
        CommissionTestData.setSetting(new Map<String, Object>{ 'Email_Enabled__c' => enabled });
    }

    // The notifications with this title that went to this user
    private static List<CommissionNotifier.Sent> sentTo(Id userId, String title) {
        List<CommissionNotifier.Sent> found = new List<CommissionNotifier.Sent>();
        for (CommissionNotifier.Sent entry : CommissionNotifier.sentLog) {
            if (entry.title == title && entry.userIds.contains(userId)) {
                found.add(entry);
            }
        }
        return found;
    }

    private static Commission_Target__c personal(Scene setup, Decimal target) {
        Commission_Target__c row = new Commission_Target__c(
            Project__c = setup.project.Id, Reference__c = setup.config.Reference__c, Config__c = setup.config.Id,
            User__c = setup.advisor.Id, Designation__c = ADVISOR, Target__c = target,
            Effective_From__c = Date.today().addDays(-1), Reason__c = 'Larger unit mix'
        );
        CommissionTargetService.bypass = true;
        try {
            insert row;
        } finally {
            CommissionTargetService.bypass = false;
        }
        return row;
    }

    @IsTest
    static void aSubmissionGoesToTheApprover() {
        Scene setup = prepare('Notify Submitted');
        Test.startTest();
        CommissionNotifier.enqueue('SUBMITTED', new Set<Id>{ setup.config.Id });
        Test.stopTest();

        List<CommissionNotifier.Sent> toApprover = sentTo(setup.approver.Id, CommissionNotifier.COMMISSION_NOTIFY_SUBMITTED_TITLE);
        System.assertEquals(1, toApprover.size(), 'The approver is told once');
        System.assertEquals(1, toApprover[0].userIds.size(), 'Only the approver');
        System.assert(toApprover[0].body.contains(setup.config.Name), 'The configuration is named: ' + toApprover[0].body);
        System.assert(toApprover[0].body.contains('Notify Submitted'), 'And its project: ' + toApprover[0].body);
        System.assertEquals(setup.config.Id, toApprover[0].configId, 'The notification opens the configuration');
        System.assertEquals('review', toApprover[0].view, 'In the review view');
        System.assertEquals(1, CommissionNotifier.sentLog.size(), 'Nobody else is told');
    }

    @IsTest
    static void anApprovalGoesToFinanceAndToEveryPayee() {
        Scene setup = prepare('Notify Approved');
        personal(setup, 23);
        Test.startTest();
        CommissionNotifier.enqueue('approved', new Set<Id>{ setup.config.Id });
        Test.stopTest();

        List<CommissionNotifier.Sent> toFinance = sentTo(setup.finance.Id, CommissionNotifier.COMMISSION_NOTIFY_APPROVED_TITLE);
        System.assertEquals(1, toFinance.size(), 'Finance (and the submitter) is told once');
        System.assert(toFinance[0].body.contains(setup.config.Name), 'The configuration is named: ' + toFinance[0].body);

        String payeeTitle = CommissionTargetService.fill(CommissionNotifier.COMMISSION_NOTIFY_PAYEE_TITLE, new List<Object>{ 'Notify Approved' });
        List<CommissionNotifier.Sent> toAdvisor = sentTo(setup.advisor.Id, payeeTitle);
        System.assertEquals(1, toAdvisor.size(), 'The advisor gets their own terms');
        System.assert(toAdvisor[0].body.contains('23'), 'With their personal target: ' + toAdvisor[0].body);
        System.assertEquals('terms', toAdvisor[0].view, 'The notification opens My terms');
        List<CommissionNotifier.Sent> toManager = sentTo(setup.manager.Id, payeeTitle);
        System.assertEquals(1, toManager.size(), 'The senior manager gets theirs');
        System.assertNotEquals(toAdvisor[0].body, toManager[0].body, 'Each designation has its own text');
    }

    @IsTest
    static void aRejectionGoesToFinanceWithTheComment() {
        Scene setup = prepare('Notify Rejected');
        Test.startTest();
        CommissionNotifier.enqueue('REJECTED', new Set<Id>{ setup.config.Id });
        Test.stopTest();

        List<CommissionNotifier.Sent> toFinance = sentTo(setup.finance.Id, CommissionNotifier.COMMISSION_NOTIFY_REJECTED_TITLE);
        System.assertEquals(1, toFinance.size(), 'Finance is told');
        System.assert(toFinance[0].body.contains('The Exceed rate is too high'), 'With the comment of the approver: ' + toFinance[0].body);
        System.assertEquals(0, sentTo(setup.advisor.Id, CommissionNotifier.COMMISSION_NOTIFY_REJECTED_TITLE).size(), 'A payee is not told about a rejection');
    }

    @IsTest
    static void aWithdrawalGoesToTheApprover() {
        Scene setup = prepare('Notify Withdrawn');
        Test.startTest();
        CommissionNotifier.enqueue('WITHDRAWN', new Set<Id>{ setup.config.Id });
        Test.stopTest();

        System.assertEquals(1, sentTo(setup.approver.Id, CommissionNotifier.COMMISSION_NOTIFY_WITHDRAWN_TITLE).size(), 'The approver is told');
        System.assertEquals(1, CommissionNotifier.sentLog.size(), 'Nobody else is');
    }

    @IsTest
    static void aTargetChangeGoesToThePersonFinanceAndTheApprover() {
        Scene setup = prepare('Notify Target');
        Commission_Target__c row = personal(setup, 12);

        Test.startTest();
        // With the ids only: the row gives the target, the day and the reason
        CommissionNotifier.enqueue('TARGET_CHANGED', new Set<Id>{ row.Id });
        List<CommissionNotifier.Sent> toPerson = sentTo(setup.advisor.Id, CommissionNotifier.COMMISSION_NOTIFY_TARGET_PERSON_TITLE);
        System.assertEquals(1, toPerson.size(), 'The person is told');
        System.assert(toPerson[0].body.contains('Larger unit mix'), 'With the reason on the row: ' + toPerson[0].body);
        List<CommissionNotifier.Sent> toFinance = sentTo(setup.finance.Id, CommissionNotifier.COMMISSION_NOTIFY_TARGET_TEAM_TITLE);
        System.assertEquals(1, toFinance.size(), 'Finance gets one summary');
        System.assert(toFinance[0].userIds.contains(setup.approver.Id), 'And so does the approver');
        System.assertEquals('targets', toFinance[0].view, 'The summary opens the Targets view');

        // From the Targets screen: what changed, from when and why
        CommissionNotifier.sentLog.clear();
        CommissionNotifier.enqueueTargets(new Map<Id, String>{ row.Id => '10 → 12' }, Date.today(), 'Agreed in the review');
        CommissionNotifier.enqueueTargets(null, Date.today(), 'Nothing');
        Test.stopTest();
        toPerson = sentTo(setup.advisor.Id, CommissionNotifier.COMMISSION_NOTIFY_TARGET_PERSON_TITLE);
        System.assertEquals(1, toPerson.size(), 'The person is told once');
        System.assert(toPerson[0].body.contains('10 → 12'), 'What changed: ' + toPerson[0].body);
        System.assert(toPerson[0].body.contains('Agreed in the review'), 'And why: ' + toPerson[0].body);
        System.assert(toPerson[0].body.contains(CommissionTargetService.formatDate(Date.today())), 'And from when: ' + toPerson[0].body);
    }

    @IsTest
    static void nothingLetsAnErrorOut() {
        Scene setup = prepare('Notify Quiet');
        Test.startTest();
        CommissionNotifier.enqueue(null, new Set<Id>{ setup.config.Id });
        CommissionNotifier.enqueue('SUBMITTED', null);
        CommissionNotifier.enqueue('SUBMITTED', new Set<Id>());
        CommissionNotifier.enqueue('NOT_AN_EVENT', new Set<Id>{ setup.config.Id });
        // An id that is not a configuration, and a target event with configuration ids
        CommissionNotifier.enqueue('APPROVED', new Set<Id>{ setup.project.Id });
        CommissionNotifier.enqueue('TARGET_CHANGED', new Set<Id>{ setup.config.Id });
        CommissionNotifier.send(null, 'Title', 'Body', null);
        CommissionNotifier.send(new Set<Id>{ null }, 'Title', 'Body', null);
        CommissionNotifier.send(new Set<Id>{ setup.finance.Id }, null, 'Body', null);
        Test.stopTest();
        System.assertEquals(0, CommissionNotifier.sentLog.size(), 'Nothing to tell, and no error');
    }

    @IsTest
    static void aNotificationOpensTheCommissionSetupTab() {
        Scene setup = prepare('Notify Send');
        Test.startTest();
        CommissionNotifier.send(new Set<Id>{ setup.finance.Id, null }, 'A title', 'A body', setup.config.Id);
        CommissionNotifier.send(new Set<Id>{ setup.finance.Id }, 'Without a configuration', null, null);
        Test.stopTest();

        System.assertEquals(2, CommissionNotifier.sentLog.size(), 'Both were handed over');
        System.assertEquals('review', CommissionNotifier.sentLog[0].view, 'With a configuration: its review');
        System.assertEquals(1, CommissionNotifier.sentLog[0].userIds.size(), 'An empty recipient is dropped');
        System.assertEquals('overview', CommissionNotifier.sentLog[1].view, 'Without one: the overview');
        System.assertEquals('Without a configuration', CommissionNotifier.sentLog[1].body, 'A missing body repeats the title');

        Map<String, Object> target = (Map<String, Object>) JSON.deserializeUntyped(CommissionNotifier.pageReference(setup.config.Id, 'review'));
        System.assertEquals('standard__navItemPage', target.get('type'), 'A tab page');
        System.assertEquals('Commission_Setup', ((Map<String, Object>) target.get('attributes')).get('apiName'), 'The Commission Setup tab');
        Map<String, Object> state = (Map<String, Object>) target.get('state');
        System.assertEquals('review', state.get('c__view'), 'The view');
        System.assertEquals(String.valueOf(setup.config.Id), state.get('c__id'), 'The configuration');
        Map<String, Object> plain = (Map<String, Object>) JSON.deserializeUntyped(CommissionNotifier.pageReference(null, 'overview'));
        System.assertEquals(false, ((Map<String, Object>) plain.get('state')).containsKey('c__id'), 'No id without a configuration');
    }

    @IsTest
    static void recipientsGoOutFiveHundredAtATime() {
        Set<Id> many = new Set<Id>();
        for (Integer i = 1; i <= 1201; i++) {
            many.add(Id.valueOf('005' + String.valueOf(i).leftPad(12, '0')));
        }
        List<Set<String>> parts = CommissionNotifier.chunks(many, 500);
        System.assertEquals(3, parts.size(), 'Three sends for 1,201 users');
        System.assertEquals(500, parts[0].size(), 'A full first part');
        System.assertEquals(500, parts[1].size(), 'A full second part');
        System.assertEquals(201, parts[2].size(), 'And the rest');
        System.assertEquals(0, CommissionNotifier.chunks(new Set<Id>(), 500).size(), 'Nobody, no send');
    }

    @IsTest
    static void theQueuedJobSendsAsWell() {
        Scene setup = prepare('Notify Queued');
        CommissionNotifier job = new CommissionNotifier('SUBMITTED', new Set<Id>{ setup.config.Id });
        job.execute(null);
        System.assertEquals(1, sentTo(setup.approver.Id, CommissionNotifier.COMMISSION_NOTIFY_SUBMITTED_TITLE).size(), 'The job does the same work');

        Test.startTest();
        Id jobId = System.enqueueJob(new CommissionNotifier('WITHDRAWN', new Set<Id>{ setup.config.Id }));
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'The job can be queued');
    }

    @IsTest
    static void anEmailFollowsWhenTheSettingAsksForIt() {
        Scene setup = prepare('Notify Email');
        useEmails(false);
        CommissionNotifier.send(new Set<Id>{ setup.finance.Id }, 'A title', 'A body', setup.config.Id);
        System.assertEquals(0, CommissionNotifier.emailsPrepared, 'No email while the setting is off');

        useEmails(true);
        Test.startTest();
        CommissionNotifier.send(new Set<Id>{ setup.finance.Id, setup.approver.Id }, 'A title', 'A body', setup.config.Id);
        Test.stopTest();
        System.assertEquals(2, CommissionNotifier.emailsPrepared, 'One email per recipient');
        System.assertEquals(2, CommissionNotifier.sentLog.size(), 'The bell notification is sent either way');
    }
}