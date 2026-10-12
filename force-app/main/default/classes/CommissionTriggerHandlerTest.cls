// The status of a configuration only moves through the approval process, so these tests submit, approve,
// reject and withdraw with the real process (Commission_Config_Approval).
@IsTest
private class CommissionTriggerHandlerTest {

    private static final Date START_DAY = Date.today().addDays(30);
    private static final Date END_DAY = Date.today().addDays(394);

    // ------------------------------------------------------------ helpers

    private static Commission_Config__c draftAs(User who, CommissionDto.Config config) {
        Commission_Config__c saved;
        System.runAs(who) {
            saved = CommissionTestData.insertDraft(config);
        }
        return saved;
    }

    private static Commission_Config__c draftAs(User who, Id projectId) {
        return draftAs(who, CommissionTestData.validDraft(projectId, START_DAY, END_DAY));
    }

    // A change made as a system step, the way the services make theirs
    private static void systemUpdate(SObject record) {
        CommissionTriggerHandler.bypass = true;
        try {
            update record;
        } finally {
            CommissionTriggerHandler.bypass = false;
        }
    }

    // What went wrong, or null
    private static String submitAs(User who, Id configId) {
        String problem = null;
        System.runAs(who) {
            try {
                Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
                request.setObjectId(configId);
                request.setSubmitterId(who.Id);
                request.setProcessDefinitionNameOrId(CommissionCatalog.setting().Approval_Process__c);
                Approval.ProcessResult result = Approval.process(request);
                if (!result.isSuccess()) {
                    problem = String.valueOf(result.getErrors());
                }
            } catch (Exception refused) {
                problem = refused.getMessage();
            }
        }
        return problem;
    }

    // Approve | Reject | Removed (withdraw). What went wrong, or null.
    private static String decideAs(User who, Id configId, String action, String comments) {
        ProcessInstanceWorkitem item = [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :configId AND ProcessInstance.Status = 'Pending'
            LIMIT 1
        ];
        // Another user takes the request over before deciding, as the screen does
        if (action != 'Removed' && item.ActorId != who.Id) {
            item.ActorId = who.Id;
            update item;
        }
        String problem = null;
        System.runAs(who) {
            try {
                Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
                request.setWorkitemId(item.Id);
                request.setAction(action);
                request.setComments(comments);
                Approval.ProcessResult result = Approval.process(request);
                if (!result.isSuccess()) {
                    problem = String.valueOf(result.getErrors());
                }
            } catch (Exception refused) {
                problem = refused.getMessage();
            }
        }
        return problem;
    }

    private static String updateProblem(SObject record) {
        try {
            update record;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
        return null;
    }

    private static String deleteProblem(SObject record) {
        try {
            delete record;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
        return null;
    }

    private static String insertProblem(SObject record) {
        try {
            insert record;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
        return null;
    }

    private static String undeleteProblem(SObject record) {
        try {
            undelete record;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
        return null;
    }

    // A delete made as a system step
    private static void systemDelete(SObject record) {
        CommissionTriggerHandler.bypass = true;
        try {
            delete record;
        } finally {
            CommissionTriggerHandler.bypass = false;
        }
    }

    // The notification with this title that was handed over for this user, or null
    private static CommissionNotifier.Sent sentTo(Id userId, String title) {
        for (CommissionNotifier.Sent entry : CommissionNotifier.sentLog) {
            if (entry.title == title && entry.userIds.contains(userId)) {
                return entry;
            }
        }
        return null;
    }

    private static Commission_Stage__c sharedStage(Id configId, String stageType) {
        for (Commission_Stage__c row : CommissionTestData.stagesOf(configId)) {
            if (String.isBlank(row.Designation__c) && row.Stage_Type__c == stageType) {
                return row;
            }
        }
        return null;
    }

    private static Commission_Rate__c rateOf(Id configId, String designation) {
        for (Commission_Rate__c row : CommissionTestData.ratesOf(configId)) {
            if (row.Designation__c == designation) {
                return row;
            }
        }
        return null;
    }

    private static Boolean has(String text, String part) {
        return text != null && text.contains(part);
    }

    // ------------------------------------------------------------ drafts

    @IsTest
    static void financeCreatesADraftAndAnOutsiderCannot() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User outsider = CommissionTestData.outsider();
        Project__c project = CommissionTestData.project('Trigger Towers');

        // Whatever is sent, a configuration starts as a draft nobody has decided
        CommissionDto.Config config = CommissionTestData.validDraft(project.Id, START_DAY, END_DAY);
        config.status = 'Approved';
        Commission_Config__c saved = draftAs(finance, config);

        System.assertEquals('Draft', saved.Status__c, 'A new configuration is a draft');
        System.assert(saved.Version__c == 1, 'Version 1');
        System.assertEquals(saved.Name, saved.Reference__c, 'A first version is its own lineage');
        System.assertEquals(saved.Name + '-v1', saved.Version_Key__c, 'The version key is reference and version');
        System.assert(has(saved.Editor_Ids__c, String.valueOf(finance.Id).left(15)), 'Whoever enters a configuration is an editor');
        System.assertEquals(6, CommissionTestData.stagesOf(saved.Id).size(), 'Stage rows are saved');
        System.assertEquals(7, CommissionTestData.ratesOf(saved.Id).size(), 'Rate rows are saved');

        System.runAs(outsider) {
            System.assertEquals(System.Label.Commission_Rule_Configure_Only,
                insertProblem(CommissionConfigValidator.headerOf(CommissionTestData.validDraft(project.Id, END_DAY.addDays(1), END_DAY.addDays(100)))),
                'Only Finance creates a configuration');
            System.assertEquals(System.Label.Commission_Rule_Configure_Only,
                updateProblem(new Commission_Config__c(Id = saved.Id, Price_Excludes_Tax__c = true)), 'Only Finance changes a configuration');
            System.assertEquals(System.Label.Commission_Rule_Configure_Only,
                updateProblem(new Commission_Stage__c(Id = sharedStage(saved.Id, 'Initial').Id, Release_Percent__c = 70)), 'Only Finance changes a stage');
            System.assertNotEquals(null, deleteProblem(saved), 'Only Finance deletes a draft');
        }
    }

    @IsTest
    static void changesOfADraftAreSavedWithTheirEditor() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User secondFinance = CommissionTestData.secondFinance();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        Commission_Stage__c initial = sharedStage(saved.Id, 'Initial');
        Commission_Stage__c mid = sharedStage(saved.Id, 'Mid');
        Commission_Stage__c finalStage = sharedStage(saved.Id, 'Final');
        Commission_Rate__c advisorRate = null;
        for (Commission_Rate__c row : CommissionTestData.ratesOf(saved.Id)) {
            if (row.Designation__c == 'Sales_Advisor') {
                advisorRate = row;
            }
        }

        System.runAs(secondFinance) {
            update new Commission_Stage__c(Id = initial.Id, Release_Percent__c = 75);
            update new Commission_Rate__c(Id = advisorRate.Id, Current_Rate__c = 1.75);
            // A row removed after a submission is switched off; before it, the row is deleted
            update new Commission_Stage__c(Id = mid.Id, Active__c = false);
            delete finalStage;
        }

        Map<Id, Commission_Stage__c> stages = new Map<Id, Commission_Stage__c>(CommissionTestData.stagesOf(saved.Id));
        System.assert(stages.get(initial.Id).Release_Percent__c == 75, 'The change of the Initial stage is saved');
        System.assert(rateOf(saved.Id, 'Sales_Advisor').Current_Rate__c == 1.75, 'So is the change of the rate');
        System.assertEquals(false, stages.get(mid.Id).Active__c, 'The Mid stage is switched off');
        System.assert(!stages.containsKey(finalStage.Id), 'The Final stage is deleted');

        Commission_Config__c reloaded = CommissionTestData.record(saved.Id);
        System.assert(has(reloaded.Editor_Ids__c, String.valueOf(finance.Id).left(15)), 'The first editor stays');
        System.assert(has(reloaded.Editor_Ids__c, String.valueOf(secondFinance.Id).left(15)), 'Whoever changes a row is an editor too');

        System.runAs(secondFinance) {
            update new Commission_Config__c(Id = saved.Id, End_Date__c = END_DAY.addDays(1), Price_Excludes_Tax__c = true);
        }
        Commission_Config__c changed = CommissionTestData.record(saved.Id);
        System.assertEquals(END_DAY.addDays(1), changed.End_Date__c, 'The change of the end date is saved');
        System.assertEquals(true, changed.Price_Excludes_Tax__c, 'So is the change of the tax option');
        System.assertEquals(reloaded.Editor_Ids__c, changed.Editor_Ids__c, 'An editor is listed once');
    }

    @IsTest
    static void aDraftThatWasNeverSubmittedCanBeDeleted() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);

        System.runAs(finance) {
            System.assertEquals(null, deleteProblem(saved), 'A draft nobody submitted can go');
        }
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c WHERE Id = :saved.Id], 'The draft is gone');
    }

    @IsTest
    static void aNewVersionKeepsItsProject() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Project__c other = CommissionTestData.project('Trigger Gardens');
        Date today = Date.today();
        Commission_Config__c inForce = CommissionTestData.insertApproved(project.Id, today.addDays(-30), today.addDays(300));

        // Version 2 of the configuration in force, and a first draft for the days after it (the headers are enough here)
        CommissionDto.Config change = CommissionTestData.validDraft(project.Id, today.addDays(1), today.addDays(300));
        change.changeType = 'Change From Date';
        change.changeReason = 'New rates';
        change.supersedesId = inForce.Id;
        change.reference = inForce.Reference__c;
        change.version = 2;
        Commission_Config__c version = CommissionConfigValidator.headerOf(change);
        Commission_Config__c first = CommissionConfigValidator.headerOf(
            CommissionTestData.validDraft(project.Id, today.addDays(301), today.addDays(600)));

        System.runAs(finance) {
            insert new List<Commission_Config__c>{ version, first };
            System.assertEquals(System.Label.Commission_Rule_Project_Fixed,
                updateProblem(new Commission_Config__c(Id = version.Id, Project__c = other.Id)),
                'A new version stays with the project of the version it was made from');
            System.assertEquals(null, updateProblem(new Commission_Config__c(Id = version.Id, Price_Excludes_Tax__c = true)),
                'Its other fields can be changed');
            System.assertEquals(null, updateProblem(new Commission_Config__c(Id = first.Id, Project__c = other.Id)),
                'The project of a first draft can still be corrected');
        }
        Commission_Config__c kept = CommissionTestData.record(version.Id);
        System.assertEquals(inForce.Id, kept.Supersedes__c, 'The draft is a version of the configuration in force');
        System.assertEquals(project.Id, kept.Project__c, 'And is still on its project');
        System.assertEquals(true, kept.Price_Excludes_Tax__c, 'The allowed change was saved');
        System.assertEquals(other.Id, CommissionTestData.record(first.Id).Project__c, 'The first draft moved');
    }

    @IsTest
    static void rowsFromTheStandardPagesFollowTheCatalog() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        Project__c project = CommissionTestData.project('Trigger Towers');
        // CP Internal is not paid yet
        CommissionDto.Config config = CommissionTestData.validDraft(project.Id, START_DAY, END_DAY);
        for (Integer i = config.rates.size() - 1; i >= 0; i--) {
            if (config.rates[i].designation == 'CP_Internal') {
                config.rates.remove(i);
            }
        }
        Commission_Config__c saved = draftAs(finance, config);
        Commission_Stage__c initial = sharedStage(saved.Id, 'Initial');
        Commission_Stage__c finalStage = sharedStage(saved.Id, 'Final');
        Commission_Rate__c advisorRate = rateOf(saved.Id, 'Sales_Advisor');
        System.assertEquals(null, rateOf(saved.Id, 'CP_Internal'), 'No rate for CP Internal yet');

        String unknownDesignation = CommissionConfigValidator.fill(
            System.Label.Commission_Rule_Designation_Invalid, new List<Object>{ 'No_Such_Designation' });
        System.runAs(finance) {
            // Rates: the designation must be one of the catalog
            System.assertEquals(unknownDesignation,
                insertProblem(new Commission_Rate__c(Config__c = saved.Id, Designation__c = 'No_Such_Designation', Current_Rate__c = 1)),
                'No rate for a designation the catalog does not have');
            System.assertEquals(System.Label.Commission_Rule_Designation_Required,
                insertProblem(new Commission_Rate__c(Config__c = saved.Id, Current_Rate__c = 1)), 'No rate without a designation');
            System.assertEquals(unknownDesignation,
                updateProblem(new Commission_Rate__c(Id = advisorRate.Id, Designation__c = 'No_Such_Designation')),
                'Nor can a rate be moved to such a designation');
            // A rate typed with the key only, and with a rate type the catalog does not give it
            System.assertEquals(null,
                insertProblem(new Commission_Rate__c(Config__c = saved.Id, Designation__c = 'CP_Internal', Rate_Type__c = 'Flat', Current_Rate__c = 0.5)),
                'A rate for a designation of the catalog is saved');

            // Stages: the payout event must be one of the catalog
            System.assertEquals(
                CommissionConfigValidator.fill(System.Label.Commission_Rule_Stage_Trigger_Invalid, new List<Object>{ System.Label.Commission_Stage_Initial }),
                updateProblem(new Commission_Stage__c(Id = initial.Id, Trigger__c = 'No_Such_Event')), 'No payout event the catalog does not have');
            System.assertEquals(null, updateProblem(new Commission_Stage__c(Id = initial.Id, Trigger__c = 'Booking_Deposit_Received')),
                'Another event of the catalog is saved');
        }

        Commission_Rate__c typed = rateOf(saved.Id, 'CP_Internal');
        System.assertEquals('CP Internal', typed.Designation_Label__c, 'The label comes from the catalog');
        System.assertEquals('Percent', typed.Rate_Type__c, 'So does the rate type, whatever was typed');
        System.assertEquals('Shared', typed.Split__c, 'The split');
        System.assertEquals('Optional', typed.Target_Rule__c, 'The target rule');
        System.assertEquals('Initial_Event', typed.Claim_Gate__c, 'The claim gate');
        System.assertEquals('At the Initial payout event', typed.Claim_Gate_Label__c, 'Its label');
        System.assertEquals('Manual', typed.Claim_Mode__c, 'And the claim mode');
        System.assertEquals('Sales_Advisor', rateOf(saved.Id, 'Sales_Advisor').Designation__c, 'The refused change was not saved');

        Commission_Stage__c moved = sharedStage(saved.Id, 'Initial');
        System.assertEquals('Booking_Deposit_Received', moved.Trigger__c, 'The new payout event is saved');
        System.assertEquals('Initial booking deposit received date', moved.Trigger_Label__c, 'With the label of the catalog');
        System.assertEquals('Date_Field', moved.Detector__c, 'Its detector');
        System.assertEquals('None', moved.Parameter_Type__c, 'And its parameter type');

        // A payout event that has left the catalog stays on the row that had it, with the values the row has
        List<Commission_Trigger__mdt> kept = new List<Commission_Trigger__mdt>();
        for (Commission_Trigger__mdt event : CommissionCatalog.testTriggers) {
            if (event.DeveloperName != 'Handover') {
                kept.add(event);
            }
        }
        CommissionCatalog.testTriggers = kept;
        System.runAs(finance) {
            System.assertEquals(null,
                updateProblem(new Commission_Stage__c(Id = finalStage.Id, Release_Percent__c = 10, Trigger_Label__c = 'Typed')),
                'A row keeps the event it had');
            System.assertEquals(
                CommissionConfigValidator.fill(System.Label.Commission_Rule_Stage_Trigger_Invalid, new List<Object>{ System.Label.Commission_Stage_Mid }),
                insertProblem(new Commission_Stage__c(Config__c = saved.Id, Stage_Type__c = 'Mid', Sequence__c = 3, Trigger__c = 'Handover', Release_Percent__c = 5)),
                'A new row cannot use it');
        }
        Commission_Stage__c stillFinal = sharedStage(saved.Id, 'Final');
        System.assertEquals('Handover', stillFinal.Trigger__c, 'The event stays');
        System.assertEquals('Handover date', stillFinal.Trigger_Label__c, 'With the label it was saved with');
    }

    // ------------------------------------------------------------ the Recycle Bin

    @IsTest
    static void aRestoredRowFollowsTheRulesOfAChange() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        Commission_Rate__c internalRate = rateOf(saved.Id, 'CP_Internal');
        System.runAs(finance) {
            delete internalRate;
        }
        // Nobody is an editor for now, so that the restore shows who it adds
        systemUpdate(new Commission_Config__c(Id = saved.Id, Editor_Ids__c = null));

        // The test runs as an administrator who does not configure
        System.assertEquals(System.Label.Commission_Rule_Configure_Only, undeleteProblem(internalRate), 'Only Finance restores a row');
        System.assertEquals(null, rateOf(saved.Id, 'CP_Internal'), 'The row stays in the Recycle Bin');
        System.runAs(finance) {
            System.assertEquals(null, undeleteProblem(internalRate), 'Finance restores a row of a draft');
        }
        System.assertNotEquals(null, rateOf(saved.Id, 'CP_Internal'), 'The row is back');
        System.assert(has(CommissionTestData.record(saved.Id).Editor_Ids__c, String.valueOf(finance.Id).left(15)),
            'Whoever restores a row is an editor');

        // Removed again and submitted: the row does not come back under a configuration that waits for approval
        System.runAs(finance) {
            delete internalRate;
        }
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits');
        String ownProfile = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name;
        CommissionTestData.setSetting(new Map<String, Object>{ 'Configure_Profiles__c' => ownProfile });
        System.assertEquals(System.Label.Commission_Rule_Pending_Locked, undeleteProblem(internalRate), 'No restore while it waits for approval');
        System.assertEquals(null, rateOf(saved.Id, 'CP_Internal'), 'The submitted configuration is unchanged');
    }

    @IsTest
    static void aRestoredConfigurationFollowsTheRulesOfAChange() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        // Nobody is an editor for now, so that the restore shows who it adds
        systemUpdate(new Commission_Config__c(Id = saved.Id, Editor_Ids__c = null));
        System.runAs(finance) {
            delete saved;
        }

        // The test runs as an administrator who does not configure
        System.assertEquals(System.Label.Commission_Rule_Configure_Only, undeleteProblem(saved), 'Only Finance restores a configuration');
        System.runAs(finance) {
            System.assertEquals(null, undeleteProblem(saved), 'Finance restores a draft');
        }
        Commission_Config__c restored = CommissionTestData.record(saved.Id);
        System.assertEquals('Draft', restored.Status__c, 'The draft is back');
        System.assertEquals(6, CommissionTestData.stagesOf(saved.Id).size(), 'With its stages');
        System.assertEquals(7, CommissionTestData.ratesOf(saved.Id).size(), 'And its rates');
        System.assert(has(restored.Editor_Ids__c, String.valueOf(finance.Id).left(15)), 'Whoever restores a configuration is an editor');

        // An approved configuration only leaves through a system step, and it does not come back
        Commission_Config__c inForce = CommissionTestData.insertApproved(project.Id, END_DAY.addDays(1), END_DAY.addDays(100));
        systemDelete(inForce);
        String ownProfile = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name;
        CommissionTestData.setSetting(new Map<String, Object>{ 'Configure_Profiles__c' => ownProfile });
        System.assertEquals(System.Label.Commission_Rule_Approved_Locked, undeleteProblem(inForce), 'No restore of an approved configuration');
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c WHERE Id = :inForce.Id], 'It stays in the Recycle Bin');
    }

    // ------------------------------------------------------------ submitting

    @IsTest
    static void theStatusCannotBeEditedDirectly() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);

        System.runAs(finance) {
            System.assertEquals(System.Label.Commission_Rule_Use_Submit,
                updateProblem(new Commission_Config__c(Id = saved.Id, Status__c = 'Pending Approval')), 'Submitting is done through the approval process');
            System.assertEquals(System.Label.Commission_Rule_Status_Change,
                updateProblem(new Commission_Config__c(Id = saved.Id, Status__c = 'Approved')), 'A draft cannot be set to Approved');
            System.assertEquals(System.Label.Commission_Rule_Status_Change,
                updateProblem(new Commission_Config__c(Id = saved.Id, Status__c = 'Superseded')), 'Nor to Superseded');
        }
        System.assertEquals('Draft', CommissionTestData.record(saved.Id).Status__c, 'Still a draft');
    }

    @IsTest
    static void submittingStampsTheRecordAndLocksIt() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        User outsider = CommissionTestData.outsider();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));

        System.assert(has(submitAs(outsider, saved.Id), System.Label.Commission_Rule_Configure_Only), 'An outsider cannot submit');
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits');

        Commission_Config__c pending = CommissionTestData.record(saved.Id);
        System.assertEquals('Pending Approval', pending.Status__c, 'The approval process sets the status');
        System.assertEquals(finance.Id, pending.Submitted_By__c, 'The submitter is stamped');
        System.assertNotEquals(null, pending.Submitted_On__c, 'With the time');

        // The test runs as an administrator, who gets past the record lock of the approval process: the trigger still refuses
        System.assertEquals(System.Label.Commission_Rule_Pending_Locked,
            updateProblem(new Commission_Config__c(Id = saved.Id, Change_Reason__c = 'Changed while waiting')), 'No change while it waits for approval');
        System.assertEquals(System.Label.Commission_Rule_Status_Change,
            updateProblem(new Commission_Config__c(Id = saved.Id, Status__c = 'Draft')), 'The status does not go back by an edit');
        System.assertEquals(System.Label.Commission_Rule_Configure_Only,
            updateProblem(new Commission_Stage__c(Id = sharedStage(saved.Id, 'Initial').Id, Release_Percent__c = 70)), 'Rows are for Finance only');

        // Even with the right to configure, the rows are locked now
        String ownProfile = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name;
        CommissionTestData.setSetting(new Map<String, Object>{ 'Configure_Profiles__c' => ownProfile });
        System.assertEquals(System.Label.Commission_Rule_Pending_Locked,
            updateProblem(new Commission_Stage__c(Id = sharedStage(saved.Id, 'Initial').Id, Release_Percent__c = 70)), 'No change of a stage while it waits');
        System.assertEquals(System.Label.Commission_Rule_Pending_Locked,
            deleteProblem(sharedStage(saved.Id, 'Mid')), 'No removal of a stage while it waits');
        System.assertEquals(System.Label.Commission_Rule_Pending_Locked,
            insertProblem(new Commission_Rate__c(Config__c = saved.Id, Designation__c = 'Extra', Active__c = true)), 'No new rate while it waits');
        System.assertEquals(System.Label.Commission_Rule_Pending_Locked, deleteProblem(pending), 'No delete while it waits');

        // An update that changes nothing is let through
        System.assertEquals(null, updateProblem(new Commission_Config__c(Id = saved.Id)), 'Nothing changed, nothing refused');
    }

    @IsTest
    static void anIncompleteOrOverlappingConfigurationIsNotSubmitted() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');

        // Stages that total 95
        CommissionDto.Config config = CommissionTestData.validDraft(project.Id, START_DAY, END_DAY);
        config.stages[2].releasePercent = 5;
        Commission_Config__c incomplete = draftAs(finance, config);
        systemUpdate(new Commission_Config__c(Id = incomplete.Id, Approver__c = approver.Id));
        String problem = submitAs(finance, incomplete.Id);
        System.assert(has(problem, CommissionConfigValidator.fill(System.Label.Commission_Rule_Stages_Total, new List<Object>{ 95 })),
            'The stages must total 100 to submit: ' + problem);
        System.assertEquals('Draft', CommissionTestData.record(incomplete.Id).Status__c, 'It stays a draft');

        // Complete, but without an approver
        systemUpdate(new Commission_Stage__c(Id = sharedStage(incomplete.Id, 'Final').Id, Release_Percent__c = 10));
        systemUpdate(new Commission_Config__c(Id = incomplete.Id, Approver__c = null));
        System.assertNotEquals(null, submitAs(finance, incomplete.Id), 'An approver must be named');

        // Complete, but on days another configuration of the project already holds
        systemUpdate(new Commission_Config__c(Id = incomplete.Id, Approver__c = approver.Id, Start_Date__c = END_DAY.addDays(1), End_Date__c = END_DAY.addDays(100)));
        Commission_Config__c inForce = CommissionTestData.insertApproved(project.Id, END_DAY.addDays(50), END_DAY.addDays(200));
        problem = submitAs(finance, incomplete.Id);
        System.assert(has(problem, inForce.Name), 'The overlap names the other configuration: ' + problem);

        // On free days it goes through
        systemUpdate(new Commission_Config__c(Id = incomplete.Id, Start_Date__c = START_DAY, End_Date__c = END_DAY));
        System.assertEquals(null, submitAs(finance, incomplete.Id), 'Complete and free of overlap');
    }

    // ------------------------------------------------------------ deciding

    @IsTest
    static void theApproverApprovesAndFinanceCannot() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User secondFinance = CommissionTestData.secondFinance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits');

        System.assert(has(decideAs(secondFinance, saved.Id, 'Approve', null), System.Label.Commission_Rule_Approve_Only), 'Finance cannot approve');
        System.assert(has(decideAs(secondFinance, saved.Id, 'Reject', 'No'), System.Label.Commission_Rule_Approve_Only), 'Finance cannot reject');
        System.assertEquals('Pending Approval', CommissionTestData.record(saved.Id).Status__c, 'Still waiting');

        CommissionNotifier.sentLog.clear();
        System.assertEquals(null, decideAs(approver, saved.Id, 'Approve', 'Agreed'), 'The approver approves');
        CommissionNotifier.Sent told = sentTo(finance.Id, System.Label.Commission_Notify_Approved_Title);
        System.assertNotEquals(null, told, 'Finance is told about the approval');
        System.assertEquals(saved.Id, told.configId, 'The notification opens the configuration');
        Commission_Config__c approved = CommissionTestData.record(saved.Id);
        System.assertEquals('Approved', approved.Status__c, 'The approval process sets the status');
        System.assertEquals(approver.Id, approved.Approved_By__c, 'The approver is stamped');
        System.assertNotEquals(null, approved.Approved_On__c, 'With the time');

        // Approved: nothing can be changed any more
        System.runAs(finance) {
            System.assertEquals(System.Label.Commission_Rule_Approved_Locked,
                updateProblem(new Commission_Config__c(Id = saved.Id, End_Date__c = END_DAY.addDays(5))), 'An approved configuration cannot be changed');
            System.assertEquals(System.Label.Commission_Rule_Approved_Locked,
                updateProblem(new Commission_Stage__c(Id = sharedStage(saved.Id, 'Initial').Id, Release_Percent__c = 70)), 'Nor its stages');
            System.assertEquals(System.Label.Commission_Rule_Approved_Locked,
                deleteProblem(CommissionTestData.ratesOf(saved.Id)[0]), 'Nor its rates');
            System.assertEquals(System.Label.Commission_Rule_Approved_Locked, deleteProblem(approved), 'And it cannot be deleted');
            System.assertEquals(System.Label.Commission_Rule_Status_Change,
                updateProblem(new Commission_Config__c(Id = saved.Id, Status__c = 'Superseded')), 'Only a service replaces a version');
        }
        systemUpdate(new Commission_Config__c(Id = saved.Id, Status__c = 'Superseded'));
        System.assertEquals('Superseded', CommissionTestData.record(saved.Id).Status__c, 'A service step may replace it');
    }

    @IsTest
    static void nobodyApprovesTheirOwnEntryUnlessAllowed() {
        CommissionTestData.useCatalog();
        // Here the approver may also configure, to become an editor of the version
        CommissionTestData.setSetting(new Map<String, Object>{
            'Configure_Roles__c' => CommissionTestData.ROLE_FINANCE + ', ' + CommissionTestData.ROLE_APPROVER
        });
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        System.runAs(approver) {
            update new Commission_Config__c(Id = saved.Id, Price_Excludes_Tax__c = true);
        }
        System.assert(has(CommissionTestData.record(saved.Id).Editor_Ids__c, String.valueOf(approver.Id).left(15)), 'The approver edited the draft');
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits');

        System.assert(has(decideAs(approver, saved.Id, 'Approve', null), System.Label.Commission_Rule_Self_Approval), 'An editor does not approve');
        System.assertEquals('Pending Approval', CommissionTestData.record(saved.Id).Status__c, 'Still waiting');

        CommissionTestData.setSetting(new Map<String, Object>{ 'Self_Approval_Profiles__c' => approver.Profile.Name });
        System.assertEquals(null, decideAs(approver, saved.Id, 'Approve', null), 'Unless the setting allows it for the profile');
        System.assertEquals('Approved', CommissionTestData.record(saved.Id).Status__c, 'Approved');
    }

    @IsTest
    static void aRejectionNeedsACommentAndReturnsTheDraft() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits');

        System.assert(has(decideAs(approver, saved.Id, 'Reject', null), System.Label.Commission_Rule_Reject_Comment), 'A rejection needs a comment');
        System.assertEquals('Pending Approval', CommissionTestData.record(saved.Id).Status__c, 'Still waiting');

        CommissionNotifier.sentLog.clear();
        System.assertEquals(null, decideAs(approver, saved.Id, 'Reject', 'Lower the Initial share'), 'With a comment it is rejected');
        CommissionNotifier.Sent told = sentTo(finance.Id, System.Label.Commission_Notify_Rejected_Title);
        System.assertNotEquals(null, told, 'Finance is told about the rejection');
        System.assert(has(told.body, 'Lower the Initial share'), 'With the comment of the approver: ' + told.body);
        Commission_Config__c returned = CommissionTestData.record(saved.Id);
        System.assertEquals('Draft', returned.Status__c, 'A rejected configuration is a draft again');
        System.assertEquals('Rejected', returned.Decision__c, 'The decision says why it is back');
        System.assertEquals('Lower the Initial share', returned.Decision_Comments__c, 'The comment is copied');
        System.assertEquals(approver.Id, returned.Decision_By__c, 'With who decided');
        System.assertNotEquals(null, returned.Decision_On__c, 'And when');

        // Finance corrects and submits again: the earlier decision is cleared
        System.runAs(finance) {
            update new Commission_Config__c(Id = saved.Id, Price_Excludes_Tax__c = true);
        }
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits again');
        Commission_Config__c again = CommissionTestData.record(saved.Id);
        System.assertEquals('Pending Approval', again.Status__c, 'Waiting again');
        System.assertEquals(null, again.Decision__c, 'The decision is cleared');
        System.assertEquals(null, again.Decision_Comments__c, 'The comment is cleared');
    }

    @IsTest
    static void aWithdrawnConfigurationIsADraftThatCanBeDeleted() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits');

        System.assertEquals(null, decideAs(finance, saved.Id, 'Removed', null), 'The submitter withdraws');
        Commission_Config__c withdrawn = CommissionTestData.record(saved.Id);
        System.assertEquals('Draft', withdrawn.Status__c, 'A withdrawn configuration is a draft again');
        System.assertEquals('Recalled', withdrawn.Decision__c, 'The decision says it was withdrawn');
        System.assertEquals(finance.Id, withdrawn.Decision_By__c, 'With who withdrew it');

        System.runAs(finance) {
            System.assertEquals(null, updateProblem(new Commission_Config__c(Id = saved.Id, Price_Excludes_Tax__c = true)), 'It can be edited again');
            System.assertEquals(null, deleteProblem(withdrawn), 'A draft that came back can be deleted');
        }
    }

    @IsTest
    static void onlyFinanceWithdraws() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Commission_Config__c saved = draftAs(finance, project.Id);
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));
        System.assertEquals(null, submitAs(finance, saved.Id), 'Finance submits');

        // The test runs as an administrator: the platform lets one recall any request, the trigger asks for the right to configure
        String problem = decideAs(new User(Id = UserInfo.getUserId()), saved.Id, 'Removed', null);
        System.assert(has(problem, System.Label.Commission_Rule_Configure_Only), 'Only Finance withdraws: ' + problem);
        Commission_Config__c waiting = CommissionTestData.record(saved.Id);
        System.assertEquals('Pending Approval', waiting.Status__c, 'Still waiting');
        System.assertEquals(null, waiting.Decision__c, 'Nothing was decided');
    }

    @IsTest
    static void aChangeFromADateIsNotApprovedOnceTheDateHasPassed() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        Project__c project = CommissionTestData.project('Trigger Towers');
        Date today = Date.today();
        Commission_Config__c inForce = CommissionTestData.insertApproved(project.Id, today.addDays(-30), today.addDays(300));
        System.assertEquals(inForce.Name, inForce.Reference__c, 'A system step stamps the lineage too');

        // Version 2 of the same configuration, applying from tomorrow
        CommissionDto.Config change = CommissionTestData.validDraft(project.Id, today.addDays(1), today.addDays(300));
        change.changeType = 'Change From Date';
        change.changeReason = 'New rates';
        change.supersedesId = inForce.Id;
        change.reference = inForce.Reference__c;
        change.version = 2;
        Commission_Config__c saved = draftAs(finance, change);
        System.assertEquals(inForce.Reference__c, saved.Reference__c, 'A further version keeps the reference');
        System.assertEquals(inForce.Reference__c + '-v2', saved.Version_Key__c, 'And has its own version key');
        systemUpdate(new Commission_Config__c(Id = saved.Id, Approver__c = approver.Id));
        System.assertEquals(null, submitAs(finance, saved.Id), 'The version it changes is not an overlap');

        // The request waited until the date had passed
        systemUpdate(new Commission_Config__c(Id = saved.Id, Start_Date__c = today.addDays(-1)));
        String problem = decideAs(approver, saved.Id, 'Approve', null);
        System.assert(has(problem, CommissionConfigValidator.fill(System.Label.Commission_Rule_Start_Passed, new List<Object>{ today.addDays(-1) })),
            'Approval is refused once the start has passed: ' + problem);

        systemUpdate(new Commission_Config__c(Id = saved.Id, Start_Date__c = today.addDays(1)));
        System.assertEquals(null, decideAs(approver, saved.Id, 'Approve', null), 'In time it is approved');
        System.assertEquals('Approved', CommissionTestData.record(saved.Id).Status__c, 'The new version is approved');
        Commission_Config__c earlier = CommissionTestData.record(inForce.Id);
        System.assertEquals(saved.Id, earlier.Superseded_By__c, 'The earlier version points to the new one');
        System.assertEquals(today, earlier.End_Date__c, 'And ends the day before the new one starts');
    }
}