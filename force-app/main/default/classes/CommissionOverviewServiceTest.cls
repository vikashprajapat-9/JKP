// The overview of Commission Setup: one row per active project, in the state its configurations put it in.
// The configurations are written directly (as a system step) in the status each situation needs; the way through
// the approval process is covered by CommissionConfigServiceTest.
@IsTest
private class CommissionOverviewServiceTest {

    private static final Date TODAY = Date.today();
    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_PENDING = 'Pending Approval';

    private static User finance;
    private static User approver;

    private static void prepare() {
        CommissionTestData.useCatalog();
        finance = CommissionTestData.finance();
        approver = CommissionTestData.approver();
        CommissionAccess.reset();
    }

    // A header without rows in the given status, written as a system step
    private static Commission_Config__c header(Id projectId, Date startDate, Date endDate, String status, String decision,
                                               String changeType, Commission_Config__c source) {
        Commission_Config__c record = new Commission_Config__c(
            Project__c = projectId,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Status__c = status,
            Decision__c = decision,
            Change_Type__c = changeType,
            Version__c = source == null ? 1 : 2,
            Supersedes__c = source == null ? null : source.Id,
            Reference__c = source == null ? null : (String.isBlank(source.Reference__c) ? source.Name : source.Reference__c),
            Submitted_By__c = status == STATUS_PENDING || decision != null ? finance.Id : null,
            Submitted_On__c = status == STATUS_PENDING || decision != null ? System.now() : null
        );
        CommissionTriggerHandler.bypass = true;
        try {
            insert record;
        } finally {
            CommissionTriggerHandler.bypass = false;
        }
        return [SELECT Id, Name, Reference__c, Version__c, Status__c FROM Commission_Config__c WHERE Id = :record.Id];
    }

    private static Commission_Config__c approved(Id projectId, Date startDate, Date endDate) {
        Id configId = CommissionTestData.insertApproved(projectId, startDate, endDate).Id;
        return [SELECT Id, Name, Reference__c, Version__c, Status__c FROM Commission_Config__c WHERE Id = :configId];
    }

    private static Map<Id, CommissionDto.ProjectRow> rowsByProject(CommissionDto.Workspace space) {
        Map<Id, CommissionDto.ProjectRow> rows = new Map<Id, CommissionDto.ProjectRow>();
        for (CommissionDto.ProjectRow row : space.projects) {
            rows.put(row.projectId, row);
        }
        return rows;
    }

    @IsTest
    static void everyProjectGetsTheRowOfItsSituation() {
        prepare();
        Project__c active = CommissionTestData.project('Overview A Active');
        Project__c ending = CommissionTestData.project('Overview B Ending');
        Project__c covered = CommissionTestData.project('Overview C Covered');
        Project__c none = CommissionTestData.project('Overview D None');
        Project__c drafted = CommissionTestData.project('Overview E Draft');
        Project__c returned = CommissionTestData.project('Overview F Returned');
        Project__c waiting = CommissionTestData.project('Overview G Waiting');
        Project__c later = CommissionTestData.project('Overview H Later');
        Project__c closed = CommissionTestData.project('Overview Z Closed');
        closed.Active__c = false;
        update closed;

        Commission_Config__c activeConfig = approved(active.Id, TODAY.addDays(-10), TODAY.addDays(300));
        Commission_Config__c endingConfig = approved(ending.Id, TODAY.addDays(-100), TODAY.addDays(3));
        // Ends soon as well, but the next period is already approved
        Commission_Config__c coveredConfig = approved(covered.Id, TODAY.addDays(-100), TODAY.addDays(3));
        Commission_Config__c coveredNext = header(covered.Id, TODAY.addDays(4), TODAY.addDays(200), 'Approved', null, 'Next Period', null);
        Commission_Config__c draftConfig = header(drafted.Id, TODAY.addDays(5), TODAY.addDays(200), STATUS_DRAFT, null, 'New', null);
        Commission_Config__c returnedConfig = header(returned.Id, TODAY.addDays(5), TODAY.addDays(200), STATUS_DRAFT, 'Rejected', 'New', null);
        // A new version of the configuration in force waits for the approver
        Commission_Config__c waitingCurrent = approved(waiting.Id, TODAY.addDays(-10), TODAY.addDays(300));
        Commission_Config__c waitingNext = header(waiting.Id, TODAY.addDays(20), TODAY.addDays(300), STATUS_PENDING, null, 'Change From Date', waitingCurrent);
        Commission_Config__c laterConfig = header(later.Id, TODAY.addDays(30), TODAY.addDays(200), 'Approved', null, 'New', null);
        approved(closed.Id, TODAY.addDays(-10), TODAY.addDays(300));

        Test.startTest();
        CommissionDto.Workspace forFinance;
        System.runAs(finance) {
            CommissionAccess.reset();
            forFinance = CommissionOverviewService.workspace();
        }
        CommissionDto.Workspace forApprover;
        System.runAs(approver) {
            CommissionAccess.reset();
            forApprover = CommissionOverviewService.workspace();
        }
        Test.stopTest();

        System.assertEquals(TODAY, forFinance.today, 'The screen is told what today is');
        System.assertEquals(true, forFinance.flags.canConfigure, 'Finance configures');
        System.assertNotEquals(null, forFinance.catalog, 'The catalog comes with the workspace');
        System.assertEquals(8, forFinance.projects.size(), 'One row per active project, none for the closed one');
        System.assertEquals('Overview A Active', forFinance.projects[0].projectName, 'The rows are in the order of the project names');
        Map<Id, CommissionDto.ProjectRow> rows = rowsByProject(forFinance);

        CommissionDto.ProjectRow row = rows.get(active.Id);
        System.assertEquals('ACTIVE', row.state, 'A configuration in force with time left');
        System.assertEquals('green', row.tone, 'Active is green');
        System.assertEquals('OPEN', row.action, 'An active configuration can be opened');
        System.assertEquals(activeConfig.Id, row.actionConfigId, 'The button opens the configuration in force');
        System.assertEquals(activeConfig.Id, row.current.id, 'The configuration in force is shown');
        System.assertEquals(300, row.daysLeft, 'Days left = end minus today');
        System.assertEquals(false, row.needsMyAction, 'Nothing to do');
        System.assertEquals(false, row.endingSoon, 'Not ending soon');
        System.assertEquals(Label.Commission_Common_None, row.nextText, 'Nothing comes next');

        row = rows.get(ending.Id);
        // The injected setting gives notice 7 days before a period ends
        System.assertEquals('ENDING', row.state, 'The period ends within the notice days and nothing follows');
        System.assertEquals('amber', row.tone, 'Ending is amber');
        System.assertEquals('NEXT_PERIOD', row.action, 'Finance starts the next period');
        System.assertEquals(endingConfig.Id, row.actionConfigId, 'The next period is made from the configuration in force');
        System.assertEquals(true, row.actionPrimary, 'The button is the main one of the row');
        System.assertEquals(true, row.needsMyAction, 'Finance must act');
        System.assertEquals(true, row.endingSoon, 'Ending soon');
        System.assertEquals(3, row.daysLeft, 'Three days left');
        System.assertEquals(true, row.nextIsWarning, 'Nothing approved comes next');
        System.assertEquals(Label.Commission_Service_Next_None_Approved, row.nextText, 'The gap is named');
        System.assertEquals(String.format(Label.Commission_Service_Ends_In_Days, new List<Object>{ '3' }), row.stateLabel, 'The state says when it ends');

        row = rows.get(covered.Id);
        System.assertEquals('ACTIVE', row.state, 'The next period is approved, so nothing is ending without cover');
        System.assertEquals(false, row.endingSoon, 'Covered');
        System.assertEquals(coveredNext.Id, row.next.id, 'The approved next period is what comes next');
        System.assert(row.nextText.contains(coveredNext.Name), 'The next configuration is named: ' + row.nextText);

        row = rows.get(none.Id);
        System.assertEquals('NO_CONFIG', row.state, 'No configuration at all');
        System.assertEquals('grey', row.tone, 'No configuration is grey');
        System.assertEquals('CONFIGURE', row.action, 'Finance configures the project');
        System.assertEquals(null, row.actionConfigId, 'There is nothing to open');
        System.assertEquals(true, row.noConfiguration, 'Flagged as without configuration');
        System.assertEquals(true, row.needsMyAction, 'Finance must act');
        System.assertEquals(null, row.current, 'Nothing in force');
        System.assertEquals(Label.Commission_Service_No_Configuration, row.stateLabel, 'The state is named');

        row = rows.get(drafted.Id);
        System.assertEquals('DRAFT', row.state, 'A draft is being worked on');
        System.assertEquals('OPEN_DRAFT', row.action, 'Finance opens the draft');
        System.assertEquals(draftConfig.Id, row.actionConfigId, 'The button opens the draft');
        System.assertEquals(true, row.hasDraft, 'Flagged as having a draft');
        System.assertEquals(true, row.noConfiguration, 'Nothing is in force yet');
        System.assertEquals(true, row.needsMyAction, 'Finance must act');
        System.assert(row.nextText.contains(draftConfig.Name), 'The draft is what comes next: ' + row.nextText);

        row = rows.get(returned.Id);
        System.assertEquals('RETURNED', row.state, 'A rejected draft is shown as returned');
        System.assertEquals('red', row.tone, 'Returned is red');
        System.assertEquals('OPEN_DRAFT', row.action, 'Finance opens the returned draft');
        System.assertEquals(returnedConfig.Id, row.actionConfigId, 'The button opens the returned draft');
        System.assertEquals(Label.Commission_State_Returned, row.stateLabel, 'The state is named');

        row = rows.get(waiting.Id);
        System.assertEquals('PENDING', row.state, 'A version waits for the approver');
        System.assertEquals('blue', row.tone, 'Waiting is blue');
        System.assertEquals('VIEW', row.action, 'Finance can only look at it');
        System.assertEquals(waitingNext.Id, row.actionConfigId, 'The button opens the waiting version');
        System.assertEquals(false, row.needsMyAction, 'Finance waits');
        System.assertEquals(true, row.withApprover, 'Flagged as with the approver');
        System.assertEquals(waitingCurrent.Id, row.current.id, 'The version in force stays in force meanwhile');
        System.assertEquals(
            String.format(Label.Commission_Service_Next_From_Date, new List<Object>{
                String.format(Label.Commission_Common_Version_Short, new List<Object>{ '2' }),
                CommissionConfigService.formatDate(TODAY.addDays(20))
            }),
            row.nextText, 'The new version of the configuration in force is described by its kind of change'
        );

        row = rows.get(later.Id);
        System.assertEquals('NO_CONFIG', row.state, 'Nothing is in force today');
        System.assertEquals('OPEN', row.action, 'The approved configuration that starts later can be opened');
        System.assertEquals(laterConfig.Id, row.actionConfigId, 'The button opens the upcoming configuration');
        System.assertEquals(false, row.needsMyAction, 'Nothing to do: a configuration is approved');

        System.assertEquals(1, forFinance.approvals.size(), 'One configuration waits for a decision');
        System.assertEquals(waitingNext.Id, forFinance.approvals[0].id, 'It is the waiting version');
        System.assertEquals('PENDING', forFinance.approvals[0].state, 'It is waiting');

        // The approver's view of the same projects
        rows = rowsByProject(forApprover);
        row = rows.get(waiting.Id);
        System.assertEquals('REVIEW', row.action, 'The approver reviews the waiting version');
        System.assertEquals(true, row.needsMyAction, 'The approver must act');
        System.assertEquals(true, row.actionPrimary, 'The button is the main one of the row');
        row = rows.get(none.Id);
        System.assertEquals('NONE', row.action, 'The approver cannot configure a project');
        System.assertEquals(false, row.needsMyAction, 'Nothing for the approver to do');
        row = rows.get(drafted.Id);
        System.assertEquals('VIEW', row.action, 'The approver can look at a draft, not work on it');
        row = rows.get(ending.Id);
        System.assertEquals('OPEN', row.action, 'The approver opens the configuration that is ending');
        System.assertEquals(false, row.needsMyAction, 'Starting the next period is not the approver\'s job');
    }

    @IsTest
    static void aRequestHeldByAnotherApproverIsOnlyViewed() {
        prepare();
        User second = CommissionTestData.secondFinance();
        // Finance users become approvers as well: a second approver who neither entered nor holds the request
        CommissionTestData.setSetting(new Map<String, Object>{
            'Approve_Roles__c' => CommissionTestData.ROLE_APPROVER + ', ' + CommissionTestData.ROLE_FINANCE
        });
        CommissionAccess.reset();
        Project__c project = CommissionTestData.project('Overview Other Approver');
        Commission_Config__c waiting = header(project.Id, TODAY, TODAY.addDays(200), STATUS_PENDING, null, 'New', null);
        // The request sits with the approver Finance chose
        CommissionTriggerHandler.bypass = true;
        try {
            update new Commission_Config__c(Id = waiting.Id, Approver__c = approver.Id);
        } finally {
            CommissionTriggerHandler.bypass = false;
        }

        Test.startTest();
        CommissionDto.Workspace forOther;
        System.runAs(second) {
            CommissionAccess.reset();
            forOther = CommissionOverviewService.workspace();
        }
        CommissionDto.Workspace forHolder;
        System.runAs(approver) {
            CommissionAccess.reset();
            forHolder = CommissionOverviewService.workspace();
        }
        Test.stopTest();

        System.assertEquals(true, forOther.flags.canApprove, 'The second user is an approver');
        CommissionDto.ProjectRow row = rowsByProject(forOther).get(project.Id);
        System.assertEquals('PENDING', row.state, 'The version waits for a decision');
        System.assertEquals(waiting.Id, row.actionConfigId, 'The button opens the waiting version');
        System.assertEquals('VIEW', row.action, 'An approver who does not hold the request can only look at it');
        System.assertEquals(Label.Commission_Service_Action_View, row.actionLabel, 'The button says so');
        System.assertEquals(false, row.needsMyAction, 'It does not wait for this approver');
        System.assertEquals(false, row.actionPrimary, 'The button is not the main one of the row');

        row = rowsByProject(forHolder).get(project.Id);
        System.assertEquals('REVIEW', row.action, 'The approver who holds the request reviews it');
        System.assertEquals(true, row.needsMyAction, 'It waits for the approver who holds it');
        System.assertEquals(true, row.actionPrimary, 'The button is the main one of the row');
    }

    @IsTest
    static void aDraftOfTheConfigurationInForceIsDescribedByItsChange() {
        prepare();
        Project__c corrected = CommissionTestData.project('Overview Correction');
        Project__c shortened = CommissionTestData.project('Overview End Early');
        Commission_Config__c first = approved(corrected.Id, TODAY.addDays(-10), TODAY.addDays(300));
        header(corrected.Id, TODAY.addDays(-10), TODAY.addDays(300), STATUS_DRAFT, null, 'Correction', first);
        Commission_Config__c second = approved(shortened.Id, TODAY.addDays(-10), TODAY.addDays(300));
        header(shortened.Id, TODAY.addDays(-10), TODAY.addDays(40), STATUS_DRAFT, null, 'End Early', second);

        Test.startTest();
        CommissionDto.Workspace space;
        System.runAs(finance) {
            CommissionAccess.reset();
            space = CommissionOverviewService.workspace();
        }
        Test.stopTest();

        Map<Id, CommissionDto.ProjectRow> rows = rowsByProject(space);
        String draftVersion = String.format(Label.Commission_Service_Next_Version_Draft, new List<Object>{ '2' });
        System.assertEquals('DRAFT', rows.get(corrected.Id).state, 'The draft decides the state of the row');
        System.assertEquals(first.Id, rows.get(corrected.Id).current.id, 'The approved version stays in force');
        System.assertEquals(
            String.format(Label.Commission_Service_Next_Correction, new List<Object>{ draftVersion }),
            rows.get(corrected.Id).nextText, 'A correction in draft'
        );
        System.assertEquals(
            String.format(Label.Commission_Service_Next_End_Early, new List<Object>{ draftVersion, CommissionConfigService.formatDate(TODAY.addDays(40)) }),
            rows.get(shortened.Id).nextText, 'An early end in draft'
        );
    }

    @IsTest
    static void aPayeeSeesNoProjectsAndAnOutsiderNothing() {
        prepare();
        User advisor = CommissionTestData.advisor();
        User outsider = CommissionTestData.outsider();
        CommissionAccess.reset();
        Project__c project = CommissionTestData.project('Overview Payee');
        approved(project.Id, TODAY.addDays(-10), TODAY.addDays(300));

        Test.startTest();
        System.runAs(advisor) {
            CommissionAccess.reset();
            CommissionDto.Workspace space = CommissionOverviewService.workspace();
            System.assertEquals(true, space.flags.isPayee, 'An advisor is paid under a designation');
            System.assertEquals(0, space.projects.size(), 'Somebody who is only paid does not see the projects');
            System.assertEquals(0, space.approvals.size(), 'Nor the approvals');
        }
        System.runAs(outsider) {
            CommissionAccess.reset();
            // Nothing but the flags, all false: the tab shows its "no access" state
            CommissionDto.Workspace space = CommissionOverviewService.workspace();
            System.assertEquals(false, space.flags.canView, 'No reading');
            System.assertEquals(false, space.flags.canConfigure, 'No configuring');
            System.assertEquals(false, space.flags.isPayee, 'Not paid under a designation');
            System.assertEquals(0, space.projects.size(), 'No projects');
            System.assertEquals(0, space.approvals.size(), 'No approvals');
            System.assertEquals(0, space.catalog.designations.size(), 'Nothing of the catalog');
        }
        Test.stopTest();
    }
}