// CommissionConfigService through the real approval process: Finance saves and submits, the approver decides,
// and every kind of change does what it should to the earlier version.
// A save, a submission and a decision are kept in different halves of a test (before and inside Test.startTest)
// so that each has its own governor limits.
@IsTest
private class CommissionConfigServiceTest {

    private static final Date TODAY = Date.today();
    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_PENDING = 'Pending Approval';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_SUPERSEDED = 'Superseded';
    // Keys of the injected catalog
    private static final String SALES_ADVISOR = 'Sales_Advisor';
    private static final String CP_INTERNAL = 'CP_Internal';
    private static final String CP_EXTERNAL = 'CP_External';
    private static final String REFERRER = 'Referrer';
    // Roles of the test users
    private static final String FINANCE_ROLE = 'Commission_Test_Finance';
    private static final String APPROVER_ROLE = 'Commission_Test_Approver';

    private static User finance;
    private static User approver;

    // The injected catalog and the two people every test needs. Users come first: they are setup objects.
    private static void prepare() {
        CommissionTestData.useCatalog();
        finance = CommissionTestData.finance();
        approver = CommissionTestData.approver();
        CommissionAccess.reset();
    }

    private static CommissionDto.Config saved(CommissionDto.Config draft, Boolean submit) {
        CommissionDto.SaveResult result = CommissionConfigService.save(draft, submit);
        System.assertEquals(true, result.saved, 'The configuration should be saved. Issues: ' + JSON.serialize(result.issues));
        System.assertEquals(submit, result.submitted, 'Submitted only when asked to');
        System.assertNotEquals(null, result.config.id, 'The saved configuration comes back with its id');
        return result.config;
    }

    private static CommissionDto.Config decided(Id configId, String decision, String comments) {
        CommissionDto.Config result;
        System.runAs(approver) {
            CommissionAccess.reset();
            result = CommissionConfigService.decide(configId, decision, comments);
        }
        CommissionAccess.reset();
        return result;
    }

    private static Commission_Config__c stored(Id configId) {
        return [
            SELECT Id, Name, Reference__c, Version__c, Version_Key__c, Project__c, Status__c, Start_Date__c, End_Date__c,
                   Original_End_Date__c, Supersedes__c, Superseded_By__c, Change_Type__c, Decision__c, Decision_Comments__c,
                   Approver__c, Approved_By__c, Submitted_By__c, Submitted_On__c, Price_Excludes_Tax__c
            FROM Commission_Config__c
            WHERE Id = :configId
        ];
    }

    private static String lineageOf(Commission_Config__c record) {
        return String.isBlank(record.Reference__c) ? record.Name : record.Reference__c;
    }

    private static CommissionDto.Rate rateOf(CommissionDto.Config config, String designation) {
        for (CommissionDto.Rate rate : config.rates) {
            if (rate.designation == designation) {
                return rate;
            }
        }
        return null;
    }

    private static Boolean hasCode(List<CommissionDto.Issue> issues, String code) {
        for (CommissionDto.Issue issue : issues) {
            if (issue.code == code) {
                return true;
            }
        }
        return false;
    }

    // A personal target of 14 for the advisor, from the first day of the configuration. Written as a system step.
    private static void insertPersonalTarget(Commission_Config__c config, Id advisorId) {
        Commission_Target__c personal = new Commission_Target__c(
            Project__c = config.Project__c,
            Reference__c = lineageOf(config),
            Config__c = config.Id,
            User__c = advisorId,
            Designation__c = SALES_ADVISOR,
            Target__c = 14,
            Effective_From__c = config.Start_Date__c,
            Reason__c = 'Agreed for this period'
        );
        CommissionTriggerHandler.bypass = true;
        try {
            insert personal;
        } finally {
            CommissionTriggerHandler.bypass = false;
        }
    }

    // Takes the Mid payouts out of the shared stages and gives their share to Final
    private static void dropMidStages(CommissionDto.Config config) {
        List<CommissionDto.Stage> kept = new List<CommissionDto.Stage>();
        Decimal moved = 0;
        for (CommissionDto.Stage stage : config.stages) {
            if (String.isBlank(stage.designation) && stage.stageType == 'Mid') {
                moved += stage.releasePercent == null ? 0 : stage.releasePercent;
            } else {
                kept.add(stage);
            }
        }
        for (CommissionDto.Stage stage : kept) {
            if (String.isBlank(stage.designation) && stage.stageType == 'Final') {
                stage.releasePercent = (stage.releasePercent == null ? 0 : stage.releasePercent) + moved;
            }
        }
        config.stages = kept;
    }

    // ------------------------------------------------------------ new configuration

    @IsTest
    static void financeSubmitsAndTheApproverApproves() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service New');
        CommissionDto.Config pending;
        System.runAs(finance) {
            CommissionAccess.reset();
            pending = saved(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364)), true);
        }
        System.assertEquals(STATUS_PENDING, pending.status, 'Submitting puts the configuration with the approver');
        System.assertEquals('PENDING', pending.state, 'The display state follows the status');
        System.assertEquals(approver.Id, pending.approverId, 'The only approver is chosen without asking');
        System.assertEquals(finance.Id, pending.submittedById, 'The submitter is recorded');
        System.assertEquals(1, pending.version, 'A new configuration is version 1');
        System.assertEquals(false, pending.canEdit, 'Nothing can be edited while it waits for approval');
        System.assertEquals(7, pending.rates.size(), 'Every designation of the catalog is listed');
        for (CommissionDto.Stage stage : pending.stages) {
            System.assertNotEquals(REFERRER, stage.designation, 'The fixed payout of a flat fee is not sent to the screen');
        }
        Commission_Stage__c fixed = [
            SELECT Stage_Type__c, Trigger__c, Trigger_Label__c, Release_Percent__c
            FROM Commission_Stage__c
            WHERE Config__c = :pending.id AND Designation__c = :REFERRER AND Active__c = true
        ];
        System.assertEquals('Initial', fixed.Stage_Type__c, 'The flat fee gets one Initial payout');
        System.assertEquals(100, fixed.Release_Percent__c.intValue(), 'The flat fee is paid in full at its fixed event');
        System.assertNotEquals(null, fixed.Trigger__c, 'The fixed event comes from the catalog');
        Commission_Rate__c advisor = [
            SELECT Designation_Label__c, Split__c, Target_Rule__c, Claim_Gate__c, Rate_Type__c
            FROM Commission_Rate__c
            WHERE Config__c = :pending.id AND Designation__c = :SALES_ADVISOR
        ];
        System.assertNotEquals(null, advisor.Designation_Label__c, 'The catalog label is copied onto the rate row');
        System.assertEquals('Shared', advisor.Split__c, 'The split kind is copied onto the rate row');

        Test.startTest();
        CommissionDto.Config approved = decided(pending.id, 'APPROVE', 'Agreed');
        Test.stopTest();

        System.assertEquals(STATUS_APPROVED, approved.status, 'The approver approved it');
        System.assertEquals('ACTIVE', approved.state, 'It starts today, so it is in force');
        Commission_Config__c record = stored(pending.id);
        System.assertEquals(approver.Id, record.Approved_By__c, 'The approver is recorded');
        System.assertEquals(lineageOf(record) + '-v1', record.Version_Key__c, 'The version key names lineage and version');
    }

    @IsTest
    static void onlyFinanceConfiguresAndOnlyTheApproverDecides() {
        prepare();
        User outsider = CommissionTestData.outsider();
        Project__c project = CommissionTestData.project('Commission Service Access');
        System.runAs(outsider) {
            CommissionAccess.reset();
            try {
                CommissionConfigService.save(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(30)), false);
                System.assert(false, 'Somebody without access cannot save a configuration');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
            try {
                CommissionConfigService.blank(project.Id);
                System.assert(false, 'Somebody without access cannot start a configuration');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c], 'Nothing was saved');

        CommissionDto.Config pending;
        System.runAs(finance) {
            CommissionAccess.reset();
            pending = saved(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(30)), true);
        }
        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            try {
                CommissionConfigService.decide(pending.id, 'APPROVE', null);
                System.assert(false, 'Finance cannot approve');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
            try {
                pending.priceExcludesTax = true;
                CommissionConfigService.save(pending, false);
                System.assert(false, 'A configuration that waits for approval cannot be edited');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
            try {
                CommissionConfigService.discard(pending.id);
                System.assert(false, 'A submitted configuration cannot be discarded');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
        }
        System.runAs(outsider) {
            CommissionAccess.reset();
            try {
                CommissionConfigService.load(pending.id);
                System.assert(false, 'Somebody without access cannot read a configuration');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
        }
        Test.stopTest();
        System.assertEquals(STATUS_PENDING, stored(pending.id).Status__c, 'It still waits for the approver');
    }

    @IsTest
    static void blankDraftOffersEveryDesignation() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Blank');
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionConfigService.blank(project.Id);
            System.assertEquals(null, draft.id, 'Nothing is stored until the first save');
            System.assertEquals(project.Id, draft.projectId, 'The draft is for the chosen project');
            System.assertEquals('New', draft.changeType, 'A blank draft is a new configuration');
            System.assertEquals('DRAFT', draft.state, 'A blank draft is a draft');
            System.assertEquals(true, draft.canEdit, 'Finance can edit it');
            System.assertEquals(false, draft.canDiscard, 'There is nothing to discard yet');
            System.assertEquals(2, draft.stages.size(), 'An empty Initial and Final payout are offered');
            System.assertEquals(7, draft.rates.size(), 'One entry per designation');
            for (CommissionDto.Rate rate : draft.rates) {
                System.assertEquals(false, rate.paid, 'No designation is paid until Finance switches it on');
            }
            System.assertEquals(1, draft.approvers.size(), 'The approver is offered');

            // An incomplete draft can be saved, but not submitted
            draft.startDate = TODAY;
            draft.endDate = TODAY.addDays(10);
            CommissionDto.SaveResult refused = CommissionConfigService.save(draft, true);
            System.assertEquals(false, refused.saved, 'An incomplete configuration is not submitted');
            System.assert(!refused.issues.isEmpty(), 'The issues say what is missing');
            System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c], 'Nothing was saved with the issues');
            CommissionDto.Config kept = saved(draft, false);
            System.assertEquals(STATUS_DRAFT, kept.status, 'The incomplete draft is kept as a draft');
            System.assertEquals(true, kept.canDiscard, 'A draft that was never submitted can be discarded');
        }
    }

    // ------------------------------------------------------------ editing a draft

    @IsTest
    static void editingADraftRemovesWhatWasTakenOut() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Edit');
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config first = saved(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364)), false);
            Integer stagesBefore = [SELECT COUNT() FROM Commission_Stage__c WHERE Config__c = :first.id];
            Integer ratesBefore = [SELECT COUNT() FROM Commission_Rate__c WHERE Config__c = :first.id];

            Test.startTest();
            // The same copy saved again changes nothing
            CommissionDto.Config same = saved(first, false);
            System.assertEquals(stagesBefore, [SELECT COUNT() FROM Commission_Stage__c WHERE Config__c = :first.id], 'No stage was added by saving again');
            System.assertEquals(ratesBefore, [SELECT COUNT() FROM Commission_Rate__c WHERE Config__c = :first.id], 'No rate was added by saving again');

            dropMidStages(same);
            rateOf(same, CP_EXTERNAL).paid = false;
            rateOf(same, REFERRER).flatAmount = 750000;
            same.priceExcludesTax = true;
            CommissionDto.Config again = saved(same, false);
            Test.stopTest();

            System.assertEquals(0, [SELECT COUNT() FROM Commission_Stage__c WHERE Config__c = :first.id AND Stage_Type__c = 'Mid'],
                'A removed stage of a draft that was never submitted is deleted');
            System.assertEquals(0, [SELECT COUNT() FROM Commission_Stage__c WHERE Config__c = :first.id AND Designation__c = :CP_EXTERNAL],
                'A designation that is not paid keeps no payout rows');
            System.assertEquals(0, [SELECT COUNT() FROM Commission_Rate__c WHERE Config__c = :first.id AND Designation__c = :CP_EXTERNAL],
                'A designation that is not paid keeps no rate row');
            System.assertEquals(750000, [SELECT Flat_Amount__c FROM Commission_Rate__c WHERE Config__c = :first.id AND Designation__c = :REFERRER].Flat_Amount__c.intValue(),
                'The changed amount is stored');
            System.assertEquals(false, rateOf(again, CP_EXTERNAL).paid, 'The screen still gets the designation, switched off');
            System.assertEquals(true, again.priceExcludesTax, 'The header change is stored');

            CommissionConfigService.discard(again.id);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c], 'The discarded draft is gone');
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Stage__c], 'Its rows went with it');
    }

    @IsTest
    static void removedRowsAreKeptOnceSubmitted() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Withdraw');
        CommissionDto.Config pending;
        System.runAs(finance) {
            CommissionAccess.reset();
            pending = saved(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364)), true);
            System.assertEquals(true, pending.canWithdraw, 'The submitter can withdraw');

            Test.startTest();
            CommissionDto.Config back = CommissionConfigService.withdraw(pending.id);
            System.assertEquals(STATUS_DRAFT, back.status, 'A withdrawn configuration is a draft again');
            System.assertEquals('Recalled', back.decision, 'The withdrawal is recorded');
            System.assertEquals('DRAFT', back.state, 'Withdrawn is not "returned"');
            System.assertEquals(true, back.canEdit, 'Finance can edit it again');
            System.assertEquals(true, back.canDiscard, 'A withdrawn draft can be discarded');

            dropMidStages(back);
            rateOf(back, CP_INTERNAL).paid = false;
            CommissionDto.Config again = saved(back, false);
            Test.stopTest();

            System.assertEquals(false, rateOf(again, CP_INTERNAL).paid, 'The designation is not paid any more');
            for (CommissionDto.Stage stage : again.stages) {
                System.assertNotEquals('Mid', stage.stageType, 'The removed stage is not shown any more');
            }
        }
        System.assertEquals(1, [SELECT COUNT() FROM Commission_Stage__c WHERE Config__c = :pending.id AND Stage_Type__c = 'Mid' AND Active__c = false],
            'Once submitted, a removed stage is switched off, not deleted');
        System.assertEquals(1, [SELECT COUNT() FROM Commission_Rate__c WHERE Config__c = :pending.id AND Designation__c = :CP_INTERNAL AND Active__c = false],
            'Once submitted, a removed rate is switched off, not deleted');
    }

    @IsTest
    static void overlapIsRefusedAndNamesTheClash() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Overlap');
        Commission_Config__c inForce = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-10), TODAY.addDays(100)).Id);
        System.runAs(finance) {
            CommissionAccess.reset();
            Test.startTest();
            CommissionDto.SaveResult result = CommissionConfigService.save(
                CommissionTestData.validDraft(project.Id, TODAY.addDays(50), TODAY.addDays(200)), false
            );
            Test.stopTest();
            System.assertEquals(false, result.saved, 'An overlapping period is not saved');
            System.assert(hasCode(result.issues, 'PERIOD_OVERLAP'), 'The overlap is reported: ' + JSON.serialize(result.issues));
            for (CommissionDto.Issue issue : result.issues) {
                if (issue.code == 'PERIOD_OVERLAP') {
                    System.assert(issue.message.contains(inForce.Name), 'The message names the configuration it clashes with');
                }
            }
        }
        System.assertEquals(1, [SELECT COUNT() FROM Commission_Config__c WHERE Project__c = :project.Id], 'Only the approved one exists');
    }

    @IsTest
    static void staleCopyIsRefused() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Stale');
        String financeName = [SELECT Name FROM User WHERE Id = :finance.Id].Name;
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config current = saved(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364)), false);
            System.assertNotEquals(null, current.lastModified, 'The screen is told when the configuration was last changed');

            Test.startTest();
            // A copy that was loaded before the latest save
            CommissionDto.Config old = CommissionConfigService.load(current.id);
            old.lastModified = current.lastModified.addMinutes(-5);
            old.priceExcludesTax = true;
            try {
                CommissionConfigService.save(old, false);
                System.assert(false, 'A copy older than the stored configuration must not overwrite it');
            } catch (AuraHandledException refused) {
                System.assert(refused.getMessage().contains(financeName), 'The refusal names who changed it: ' + refused.getMessage());
            }
            System.assertEquals(false, stored(current.id).Price_Excludes_Tax__c, 'Nothing was written');

            current.priceExcludesTax = true;
            CommissionDto.Config latest = saved(current, false);
            Test.stopTest();
            System.assertEquals(true, latest.priceExcludesTax, 'The current copy saves');
        }
    }

    @IsTest
    static void aRowRemovedByAnotherEditorMakesOlderCopiesStale() {
        prepare();
        User second = CommissionTestData.secondFinance();
        CommissionAccess.reset();
        Project__c project = CommissionTestData.project('Commission Service Stale Removal');
        String financeName = [SELECT Name FROM User WHERE Id = :finance.Id].Name;
        CommissionDto.Config first;
        System.runAs(finance) {
            CommissionAccess.reset();
            first = saved(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364)), false);
        }

        Test.startTest();
        // The second editor changes the header: the newest change is theirs, and the copy they hold is current
        CommissionDto.Config theirs;
        System.runAs(second) {
            CommissionAccess.reset();
            first.priceExcludesTax = true;
            theirs = saved(first, false);
        }
        System.assertEquals(second.Id, [SELECT LastModifiedById FROM Commission_Config__c WHERE Id = :first.id].LastModifiedById,
            'The second editor changed the header last');

        // Finance then stops paying a designation: its rate row is deleted and no other row changes
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config mine = CommissionConfigService.load(first.id);
            rateOf(mine, CP_INTERNAL).paid = false;
            saved(mine, false);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Rate__c WHERE Config__c = :first.id AND Designation__c = :CP_INTERNAL],
            'The rate of a draft that was never submitted is deleted');
        System.assertEquals(finance.Id, [SELECT LastModifiedById FROM Commission_Config__c WHERE Id = :first.id].LastModifiedById,
            'The header carries the removal: nothing else is left that an older copy could be compared with');

        // The second editor still holds the copy with that designation. Stored times have whole seconds, so the copy
        // is made a little older instead of waiting.
        System.runAs(second) {
            CommissionAccess.reset();
            theirs.lastModified = theirs.lastModified.addMinutes(-5);
            try {
                CommissionConfigService.save(theirs, false);
                System.assert(false, 'A copy from before the removal must not put the removed row back');
            } catch (AuraHandledException refused) {
                System.assert(refused.getMessage().contains(financeName), 'The refusal names who removed the row: ' + refused.getMessage());
            }
        }
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Rate__c WHERE Config__c = :first.id AND Designation__c = :CP_INTERNAL],
            'The removed rate did not come back');
    }

    // ------------------------------------------------------------ approval decisions

    @IsTest
    static void rejectionNeedsACommentAndReturnsTheDraft() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Reject');
        CommissionDto.Config pending;
        System.runAs(finance) {
            CommissionAccess.reset();
            pending = saved(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364)), true);
        }

        Test.startTest();
        System.runAs(approver) {
            CommissionAccess.reset();
            CommissionDto.Config seen = CommissionConfigService.load(pending.id);
            System.assertEquals(true, seen.canDecide, 'The approver may decide');
            System.assertEquals(null, seen.decideBlockedReason, 'Nothing stands in the way');
            try {
                CommissionConfigService.decide(pending.id, 'REJECT', '   ');
                System.assert(false, 'A rejection needs a comment');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Reject_Needs_Comment, refused.getMessage(), 'The refusal asks for the comment');
            }
            try {
                CommissionConfigService.decide(pending.id, 'MAYBE', 'No');
                System.assert(false, 'Only Approve and Reject are decisions');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Decision_Invalid, refused.getMessage(), 'The refusal says what is possible');
            }
        }
        System.assertEquals(STATUS_PENDING, stored(pending.id).Status__c, 'Still waiting after the refused attempts');
        CommissionDto.Config returned = decided(pending.id, 'REJECT', 'The Final payout is too low');
        Test.stopTest();

        System.assertEquals(STATUS_DRAFT, returned.status, 'A rejected configuration goes back to Draft');
        System.assertEquals('RETURNED', returned.state, 'It is shown as returned');
        System.assertEquals('Rejected', returned.decision, 'The decision is recorded');
        System.assertEquals('The Final payout is too low', returned.decisionComments, 'Finance sees the comment');
        System.assertEquals(Label.Commission_State_Returned, returned.stateLabel, 'The state is named for the screen');
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config reopened = CommissionConfigService.load(pending.id);
            System.assertEquals(true, reopened.canEdit, 'Finance can correct the returned draft');
            System.assertEquals(true, reopened.canDiscard, 'A returned draft can be discarded');
        }
    }

    @IsTest
    static void nobodyDecidesTheirOwnEntry() {
        prepare();
        User second = CommissionTestData.secondFinance();
        // Finance users become approvers as well: the one who entered the version still may not decide it
        CommissionTestData.setSetting(new Map<String, Object>{ 'Approve_Roles__c' => APPROVER_ROLE + ', ' + FINANCE_ROLE });
        CommissionAccess.reset();
        Project__c project = CommissionTestData.project('Commission Service Own Entry');
        CommissionDto.Config pending;
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364));
            draft.approverId = null;
            try {
                CommissionConfigService.save(draft, true);
                System.assert(false, 'With several approvers Finance must choose one');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Choose_Approver, refused.getMessage(), 'The refusal asks for the choice');
            }
            System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c], 'A refused submission leaves nothing half-saved');
            draft.approverId = approver.Id;
            pending = saved(draft, true);
            System.assertEquals(approver.Id, pending.approverId, 'The chosen approver gets the request');
        }

        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config seen = CommissionConfigService.load(pending.id);
            System.assertEquals(false, seen.canDecide, 'Who entered the version cannot decide it');
            System.assertEquals(Label.Commission_Service_Decide_Blocked, seen.decideBlockedReason, 'The screen is told why');
            try {
                CommissionConfigService.decide(pending.id, 'APPROVE', null);
                System.assert(false, 'Who entered the version cannot approve it');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Decide_Blocked, refused.getMessage(), 'The refusal says why');
            }
        }
        // Another approver who is not an administrator cannot take the request over: they are told who holds it
        System.runAs(second) {
            CommissionAccess.reset();
            CommissionDto.Config seen = CommissionConfigService.load(pending.id);
            System.assertEquals(false, seen.canDecide, 'The request sits with the approver Finance chose');
            String holder = [SELECT Name FROM User WHERE Id = :approver.Id WITH SYSTEM_MODE].Name;
            System.assert(seen.decideBlockedReason != null && seen.decideBlockedReason.contains(holder),
                'The screen names who holds the request: ' + seen.decideBlockedReason);
            try {
                CommissionConfigService.decide(pending.id, 'APPROVE', 'Checked');
                System.assert(false, 'Only the approver who holds the request, or an administrator, decides it');
            } catch (AuraHandledException refused) {
                System.assertEquals(seen.decideBlockedReason, refused.getMessage(), 'The refusal says who holds it');
            }
        }
        System.runAs(approver) {
            CommissionAccess.reset();
            CommissionDto.Config seen = CommissionConfigService.load(pending.id);
            System.assertEquals(true, seen.canDecide, 'The approver who holds the request may decide');
            CommissionDto.Config approved = CommissionConfigService.decide(pending.id, 'APPROVE', 'Checked');
            System.assertEquals(STATUS_APPROVED, approved.status, 'The chosen approver approved it');
        }
        Test.stopTest();
        System.assertEquals(approver.Id, stored(pending.id).Approved_By__c, 'Who really approved is recorded');
    }

    // ------------------------------------------------------------ new drafts from an approved configuration

    @IsTest
    static void correctionReplacesTheEarlierVersion() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Correction');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-30), TODAY.addDays(300)).Id);
        CommissionDto.Config pending;
        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionConfigService.draftFrom(earlier.Id, 'CORRECTION', null);
            System.assertEquals(null, draft.id, 'Nothing is stored until the first save');
            System.assertEquals('Correction', draft.changeType, 'The draft is a correction');
            System.assertEquals(earlier.Id, draft.supersedesId, 'It will replace the approved version');
            System.assertEquals(2, draft.version, 'It is the next version');
            System.assertEquals(lineageOf(earlier), draft.reference, 'It stays in the same lineage');
            System.assertEquals(earlier.Start_Date__c, draft.startDate, 'A correction keeps the start');
            System.assertEquals(earlier.End_Date__c, draft.endDate, 'A correction keeps the end');
            System.assertEquals('SUPERSEDES', draft.baselineKind, 'It is compared with the version it replaces');
            System.assertNotEquals(null, draft.baseline, 'The version it replaces comes with it');
            System.assert(String.isNotBlank(draft.consequence), 'The consequence is spelled out');
            for (CommissionDto.Stage stage : draft.stages) {
                System.assertEquals(null, stage.id, 'Copied rows are new rows');
            }
            draft.changeReason = 'The Exceed rate of the Sales Advisor was entered wrongly';
            CommissionDto.Rate advisor = rateOf(draft, SALES_ADVISOR);
            advisor.exceedRate = advisor.exceedRate + 1;
            pending = saved(draft, true);
        }
        Test.stopTest();
        System.assertEquals(2, pending.version, 'The saved draft is version 2');
        System.assertEquals(earlier.Id, pending.supersedesId, 'The saved draft points at the version it replaces');

        decided(pending.id, 'APPROVE', null);
        Commission_Config__c before = stored(earlier.Id);
        Commission_Config__c after = stored(pending.id);
        System.assertEquals(STATUS_APPROVED, after.Status__c, 'The correction is approved');
        System.assertEquals(lineageOf(earlier), after.Reference__c, 'Same lineage');
        System.assertEquals(lineageOf(earlier) + '-v2', after.Version_Key__c, 'The version key names lineage and version');
        System.assertEquals(STATUS_SUPERSEDED, before.Status__c, 'The earlier version is replaced completely');
        System.assertEquals(after.Id, before.Superseded_By__c, 'The earlier version names its successor');
        System.assertEquals(earlier.End_Date__c, before.End_Date__c, 'A replaced version keeps its dates');
    }

    @IsTest
    static void changeFromDateShortensTheEarlierVersion() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Change');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-30), TODAY.addDays(300)).Id);
        CommissionDto.Config pending;
        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionConfigService.draftFrom(earlier.Id, 'CHANGE_FROM_DATE', null);
            System.assertEquals('Change From Date', draft.changeType, 'The draft changes the terms from a date');
            System.assertEquals(TODAY.addDays(1), draft.startDate, 'The change starts tomorrow at the earliest');
            System.assertEquals(earlier.End_Date__c, draft.endDate, 'It runs to the end of the period');
            draft.changeReason = 'New terms agreed with the CCO';
            pending = saved(draft, true);
        }
        Test.stopTest();

        decided(pending.id, 'APPROVE', 'Agreed');
        Commission_Config__c before = stored(earlier.Id);
        Commission_Config__c after = stored(pending.id);
        System.assertEquals(STATUS_APPROVED, after.Status__c, 'The new version is approved');
        System.assertEquals(STATUS_APPROVED, before.Status__c, 'The earlier version stays approved for earlier sales');
        System.assertEquals(TODAY, before.End_Date__c, 'The earlier version ends the day before the new one starts');
        System.assertEquals(earlier.End_Date__c, before.Original_End_Date__c, 'Its planned end is kept');
        System.assertEquals(after.Id, before.Superseded_By__c, 'The earlier version names its successor');
        System.assertEquals('ACTIVE', CommissionConfigService.stateOf(before, TODAY), 'The earlier version is in force until its last day');
        System.assertEquals('UPCOMING', CommissionConfigService.stateOf(after, TODAY), 'The new version starts tomorrow');
    }

    @IsTest
    static void endEarlyBringsTheEndForward() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service End Early');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-30), TODAY.addDays(300)).Id);
        CommissionDto.Config pending;
        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionConfigService.draftFrom(earlier.Id, 'END_EARLY', null);
            System.assertEquals('End Early', draft.changeType, 'The draft ends the period early');
            System.assertEquals(earlier.Start_Date__c, draft.startDate, 'The start stays');
            System.assertEquals(TODAY, draft.endDate, 'The period ends today unless Finance picks a later day');
            draft.changeReason = 'The project is sold out';
            pending = saved(draft, true);
        }
        Test.stopTest();

        decided(pending.id, 'APPROVE', null);
        Commission_Config__c before = stored(earlier.Id);
        Commission_Config__c after = stored(pending.id);
        System.assertEquals(STATUS_APPROVED, after.Status__c, 'The shorter version is approved');
        System.assertEquals(TODAY, after.End_Date__c, 'The period now ends today');
        System.assertEquals(STATUS_SUPERSEDED, before.Status__c, 'The earlier version is replaced');
        System.assertEquals(after.Id, before.Superseded_By__c, 'The earlier version names its successor');
    }

    @IsTest
    static void nextPeriodCarriesPersonalTargetsOver() {
        prepare();
        User advisor = CommissionTestData.advisor();
        CommissionAccess.reset();
        Project__c project = CommissionTestData.project('Commission Service Next');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-100), TODAY.addDays(10)).Id);
        insertPersonalTarget(earlier, advisor.Id);

        CommissionDto.Config pending;
        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionConfigService.draftFrom(earlier.Id, 'NEXT_PERIOD', null);
            System.assertEquals('Next Period', draft.changeType, 'The draft is the next period');
            System.assertEquals(null, draft.supersedesId, 'A next period replaces nothing');
            System.assertEquals(null, draft.reference, 'A next period starts a new lineage');
            System.assertEquals(1, draft.version, 'A new lineage starts at version 1');
            System.assertEquals(earlier.End_Date__c.addDays(1), draft.startDate, 'It starts the day after the current period ends');
            System.assertEquals(draft.startDate.addDays(110), draft.endDate, 'It is as long as the current period');
            System.assertEquals(true, draft.carryOverTargets, 'Personal targets are carried over unless Finance says no');
            System.assertEquals('PREVIOUS_PERIOD', draft.baselineKind, 'It is compared with the period before');
            draft.changeReason = 'Same terms for the next period';
            pending = saved(draft, true);
        }
        Test.stopTest();
        System.assertEquals('PREVIOUS_PERIOD', pending.baselineKind, 'The saved draft is still compared with the period before');
        System.assert(String.isNotBlank(pending.consequence), 'The consequence names the period it follows');

        decided(pending.id, 'APPROVE', null);
        Commission_Config__c before = stored(earlier.Id);
        Commission_Config__c after = stored(pending.id);
        System.assertEquals(STATUS_APPROVED, after.Status__c, 'The next period is approved');
        System.assertNotEquals(lineageOf(earlier), lineageOf(after), 'It is a lineage of its own');
        System.assertEquals(STATUS_APPROVED, before.Status__c, 'The current period is untouched');
        System.assertEquals(null, before.Superseded_By__c, 'Nothing replaced the current period');
        String newLineage = lineageOf(after);
        List<Commission_Target__c> carried = [
            SELECT User__c, Designation__c, Target__c, Effective_From__c
            FROM Commission_Target__c
            WHERE Project__c = :project.Id AND Reference__c = :newLineage
        ];
        System.assertEquals(1, carried.size(), 'The personal target moved on to the next period');
        System.assertEquals(advisor.Id, carried[0].User__c, 'It is still the advisor who has it');
        System.assertEquals(14, carried[0].Target__c.intValue(), 'The target is the same');
        System.assertEquals(after.Start_Date__c, carried[0].Effective_From__c, 'It applies from the first day of the next period');
    }

    @IsTest
    static void nextPeriodFollowsAPeriodThatEndedEarlier() {
        prepare();
        User advisor = CommissionTestData.advisor();
        CommissionAccess.reset();
        Project__c project = CommissionTestData.project('Commission Service Next Gap');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-100), TODAY.addDays(10)).Id);
        insertPersonalTarget(earlier, advisor.Id);

        CommissionDto.Config pending;
        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionConfigService.draftFrom(earlier.Id, 'NEXT_PERIOD', null);
            draft.changeReason = 'Same terms for the next period';
            pending = saved(draft, true);
        }
        Test.stopTest();
        System.assertEquals(earlier.End_Date__c.addDays(1), pending.startDate, 'It was submitted to start the day after the current period ends');

        // While it waits for approval the current period is ended five days sooner (a system step here)
        CommissionTriggerHandler.bypass = true;
        try {
            update new Commission_Config__c(Id = earlier.Id, End_Date__c = earlier.End_Date__c.addDays(-5));
        } finally {
            CommissionTriggerHandler.bypass = false;
        }

        CommissionDto.Config next = decided(pending.id, 'APPROVE', null);
        System.assertEquals(STATUS_APPROVED, next.status, 'The next period is approved');
        System.assertEquals('PREVIOUS_PERIOD', next.baselineKind, 'It is still compared with the period before');
        System.assertNotEquals(null, next.baseline, 'The period before comes with it');
        System.assertEquals(earlier.Id, next.baseline.id, 'The period before is the one that ended last before it starts');
        Commission_Config__c after = stored(pending.id);
        String newLineage = lineageOf(after);
        List<Commission_Target__c> carried = [
            SELECT User__c, Target__c, Effective_From__c
            FROM Commission_Target__c
            WHERE Project__c = :project.Id AND Reference__c = :newLineage
        ];
        System.assertEquals(1, carried.size(), 'The personal target moved on although the periods no longer touch');
        System.assertEquals(advisor.Id, carried[0].User__c, 'It is still the advisor who has it');
        System.assertEquals(14, carried[0].Target__c.intValue(), 'The target is the same');
        System.assertEquals(after.Start_Date__c, carried[0].Effective_From__c, 'It applies from the first day of the next period');
    }

    @IsTest
    static void copyGoesToAnotherProject() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Copy From');
        Project__c other = CommissionTestData.project('Commission Service Copy To');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-30), TODAY.addDays(300)).Id);
        CommissionDto.Config pending;
        Test.startTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            try {
                CommissionConfigService.draftFrom(earlier.Id, 'COPY', null);
                System.assert(false, 'A copy needs a project');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Project_Required, refused.getMessage(), 'The refusal asks for the project');
            }
            try {
                CommissionConfigService.draftFrom(earlier.Id, 'COPY', project.Id);
                System.assert(false, 'A copy goes to another project');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Copy_Same_Project, refused.getMessage(), 'The refusal asks for another project');
            }
            try {
                CommissionConfigService.draftFrom(earlier.Id, 'SOMETHING', null);
                System.assert(false, 'Only the five choices exist');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Choice_Invalid, refused.getMessage(), 'The refusal says so');
            }
            CommissionDto.Config draft = CommissionConfigService.draftFrom(earlier.Id, 'COPY', other.Id);
            System.assertEquals('Copy', draft.changeType, 'The draft is a copy');
            System.assertEquals(other.Id, draft.projectId, 'It belongs to the other project');
            System.assertEquals(null, draft.startDate, 'The copy gets its own period');
            System.assertEquals(null, draft.supersedesId, 'A copy replaces nothing');
            System.assertEquals(null, draft.baseline, 'A copy has nothing to be compared with');
            draft.startDate = TODAY;
            draft.endDate = TODAY.addDays(100);
            draft.changeReason = 'Same terms as the first project';
            pending = saved(draft, true);
        }
        Test.stopTest();

        decided(pending.id, 'APPROVE', null);
        Commission_Config__c before = stored(earlier.Id);
        Commission_Config__c after = stored(pending.id);
        System.assertEquals(STATUS_APPROVED, after.Status__c, 'The copy is approved');
        System.assertEquals(other.Id, after.Project__c, 'The copy is a configuration of the other project');
        System.assertEquals(1, after.Version__c.intValue(), 'The copy is a first version');
        System.assertNotEquals(lineageOf(earlier), lineageOf(after), 'The copy is a lineage of its own');
        System.assertEquals(STATUS_APPROVED, before.Status__c, 'The source is untouched');
        System.assertEquals(null, before.Superseded_By__c, 'Nothing replaced the source');
    }

    @IsTest
    static void aSecondOpenDraftIsRefused() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Second Draft');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-30), TODAY.addDays(300)).Id);
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config source = CommissionConfigService.load(earlier.Id);
            System.assertEquals(true, source.canCreateFrom, 'Finance can make a new draft from an approved configuration');

            CommissionDto.Config draft = CommissionConfigService.draftFrom(earlier.Id, 'CORRECTION', null);
            draft.changeReason = 'First correction';
            Test.startTest();
            CommissionDto.Config first = saved(draft, false);
            System.assertEquals(STATUS_DRAFT, first.status, 'The correction is a draft');
            System.assertEquals(2, first.version, 'The correction is version 2');
            System.assertEquals(true, first.canDiscard, 'A draft that was never submitted can be discarded');

            try {
                CommissionConfigService.draftFrom(earlier.Id, 'CHANGE_FROM_DATE', null);
                System.assert(false, 'Only one open draft may replace the same version');
            } catch (AuraHandledException refused) {
                System.assert(refused.getMessage().contains(first.name), 'The refusal names the open draft: ' + refused.getMessage());
            }
            // The copy that was on the screen before the first save cannot become a second draft either
            try {
                CommissionConfigService.save(draft, false);
                System.assert(false, 'Only one open draft may replace the same version');
            } catch (AuraHandledException refused) {
                System.assert(refused.getMessage().contains(first.name), 'The refusal names the open draft: ' + refused.getMessage());
            }
            source = CommissionConfigService.load(earlier.Id);
            Test.stopTest();
            System.assertEquals(false, source.canCreateFrom, 'No second draft while one is open');
            System.assertEquals(first.id, source.openDraftId, 'The approved version points at its open draft');
            System.assertEquals(first.name, source.openDraftName, 'The open draft is named');
        }
        System.assertEquals(2, [SELECT COUNT() FROM Commission_Config__c WHERE Project__c = :project.Id], 'The approved version and one draft');
    }

    @IsTest
    static void aVersionOfAnotherProjectReplacesNothing() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Service Own Project');
        Project__c other = CommissionTestData.project('Commission Service Other Project');
        Commission_Config__c earlier = stored(CommissionTestData.insertApproved(project.Id, TODAY.addDays(-30), TODAY.addDays(300)).Id);
        // Two versions that name the earlier one as their source but belong to another project. Written as a system
        // step: the screens never change the project of a new version.
        List<Commission_Config__c> elsewhere = new List<Commission_Config__c>{
            new Commission_Config__c(
                Project__c = other.Id, Start_Date__c = earlier.Start_Date__c, End_Date__c = earlier.End_Date__c,
                Status__c = STATUS_APPROVED, Change_Type__c = 'Correction', Version__c = 2, Supersedes__c = earlier.Id,
                Reference__c = lineageOf(earlier), Change_Reason__c = 'Project changed off the screen'
            ),
            new Commission_Config__c(
                Project__c = other.Id, Start_Date__c = TODAY.addDays(1), End_Date__c = earlier.End_Date__c,
                Status__c = STATUS_APPROVED, Change_Type__c = 'Change From Date', Version__c = 3, Supersedes__c = earlier.Id,
                Reference__c = lineageOf(earlier), Change_Reason__c = 'Project changed off the screen'
            )
        };
        CommissionTriggerHandler.bypass = true;
        try {
            insert elsewhere;
        } finally {
            CommissionTriggerHandler.bypass = false;
        }

        Test.startTest();
        CommissionConfigService.afterApproval(elsewhere);
        Commission_Config__c untouched = stored(earlier.Id);
        System.assertEquals(STATUS_APPROVED, untouched.Status__c, 'A version of another project does not replace this one');
        System.assertEquals(null, untouched.Superseded_By__c, 'Nothing of another project is named as the successor');
        System.assertEquals(earlier.End_Date__c, untouched.End_Date__c, 'A version of another project does not shorten the period');
        System.assertEquals(null, untouched.Original_End_Date__c, 'The period was never shortened');

        // The same correction on the project of the earlier version does replace it
        Commission_Config__c correction = elsewhere[0];
        correction.Project__c = project.Id;
        CommissionTriggerHandler.bypass = true;
        try {
            update correction;
        } finally {
            CommissionTriggerHandler.bypass = false;
        }
        CommissionConfigService.afterApproval(new List<Commission_Config__c>{ correction });
        Test.stopTest();
        Commission_Config__c replaced = stored(earlier.Id);
        System.assertEquals(STATUS_SUPERSEDED, replaced.Status__c, 'A version of the same project replaces the earlier one');
        System.assertEquals(correction.Id, replaced.Superseded_By__c, 'The earlier version names its successor');
    }

    // ------------------------------------------------------------ states and texts (no data needed)

    @IsTest
    static void statesFollowStatusAndDates() {
        Commission_Config__c record = new Commission_Config__c(Status__c = STATUS_DRAFT);
        System.assertEquals('DRAFT', CommissionConfigService.stateOf(record, TODAY), 'A draft');
        System.assertEquals(Label.Commission_State_Draft, CommissionConfigService.stateLabel(record, TODAY), 'A draft, in words');
        record.Decision__c = 'Rejected';
        System.assertEquals('RETURNED', CommissionConfigService.stateOf(record, TODAY), 'A rejected draft is returned');
        record.Decision__c = 'Recalled';
        System.assertEquals('DRAFT', CommissionConfigService.stateOf(record, TODAY), 'A withdrawn draft is a draft');

        record = new Commission_Config__c(Status__c = STATUS_PENDING);
        System.assertEquals('PENDING', CommissionConfigService.stateOf(record, TODAY), 'Waiting for approval');
        System.assertEquals(Label.Commission_State_Pending_Short, CommissionConfigService.stateLabel(record, TODAY), 'Without a submission time the short text is used');
        record.Submitted_On__c = Datetime.newInstance(2026, 10, 8, 9, 30, 0);
        System.assertEquals(
            String.format(Label.Commission_State_Pending, new List<Object>{ CommissionConfigService.formatDay(Date.newInstance(2026, 10, 8)) }),
            CommissionConfigService.stateLabel(record, TODAY), 'The text says since when it waits'
        );

        record = new Commission_Config__c(Status__c = STATUS_APPROVED, Start_Date__c = TODAY.addDays(5), End_Date__c = TODAY.addDays(50));
        System.assertEquals('UPCOMING', CommissionConfigService.stateOf(record, TODAY), 'Approved and still to start');
        System.assertEquals('ACTIVE', CommissionConfigService.stateOf(record, TODAY.addDays(5)), 'In force on its first day');
        System.assertEquals('ACTIVE', CommissionConfigService.stateOf(record, TODAY.addDays(50)), 'In force on its last day');
        System.assertEquals('EXPIRED', CommissionConfigService.stateOf(record, TODAY.addDays(51)), 'Over and not replaced');
        System.assertEquals(Label.Commission_State_Expired, CommissionConfigService.stateLabel(record, TODAY.addDays(51)), 'Expired, in words');
        record.Superseded_By__c = Commission_Config__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        System.assertEquals('ACTIVE', CommissionConfigService.stateOf(record, TODAY.addDays(10)), 'A shortened version is in force until its last day');
        System.assertEquals('REPLACED', CommissionConfigService.stateOf(record, TODAY.addDays(51)), 'A shortened version is replaced afterwards');
        System.assertEquals(Label.Commission_State_Replaced_Short, CommissionConfigService.stateLabel(record, TODAY.addDays(51)), 'Without the newer version the short text is used');

        record = new Commission_Config__c(Status__c = STATUS_SUPERSEDED, Start_Date__c = TODAY, End_Date__c = TODAY.addDays(50));
        System.assertEquals('REPLACED', CommissionConfigService.stateOf(record, TODAY), 'A superseded version is replaced');
        System.assertEquals(null, CommissionConfigService.stateOf(null, TODAY), 'No record, no state');

        CommissionDto.Summary summary = CommissionConfigService.summary(record);
        System.assertEquals('REPLACED', summary.state, 'The summary carries the state');
        System.assertEquals(TODAY, summary.startDate, 'The summary carries the period');
        System.assertEquals(null, CommissionConfigService.summary(null), 'No record, no summary');

        System.assertEquals('01 Sep 2026', CommissionConfigService.formatDate(Date.newInstance(2026, 9, 1)), 'Dates read as 01 Sep 2026');
        System.assertEquals('', CommissionConfigService.formatDate(null), 'No date, no text');
    }

    @IsTest
    static void triggerMessagesAreShownWithoutThePlatformWrapping() {
        System.assertEquals(
            'Use Submit for approval in Commission Setup.',
            CommissionConfigService.tidyMessage(
                'Update failed. First exception on row 0 with id a0X000000000001AAA; first error: '
                    + 'FIELD_CUSTOM_VALIDATION_EXCEPTION, Use Submit for approval in Commission Setup.: []'
            ),
            'Only the message of the rule is left'
        );
        System.assertEquals('Plain text', CommissionConfigService.tidyMessage('Plain text'), 'A plain message stays as it is');
        System.assertEquals('', CommissionConfigService.tidyMessage(null), 'No message, no text');
        System.assertEquals('', CommissionConfigService.messageOf(null), 'No exception, no text');
        try {
            insert new Commission_Config__c();
            System.assert(false, 'A configuration needs a project and a period');
        } catch (Exception problem) {
            System.assert(String.isNotBlank(CommissionConfigService.messageOf(problem)), 'The message of a failed save is readable');
        }
    }

    @IsTest
    static void whatDoesNotExistIsReported() {
        prepare();
        System.runAs(finance) {
            CommissionAccess.reset();
            try {
                CommissionConfigService.load(null);
                System.assert(false, 'There is nothing to load');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Not_Found, refused.getMessage(), 'The refusal says it is gone');
            }
            try {
                CommissionConfigService.save(null, false);
                System.assert(false, 'There is nothing to save');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Nothing_To_Save, refused.getMessage(), 'The refusal says so');
            }
            try {
                CommissionConfigService.discard(null);
                System.assert(false, 'There is nothing to discard');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Not_Found, refused.getMessage(), 'The refusal says it is gone');
            }
            try {
                CommissionConfigService.withdraw(null);
                System.assert(false, 'There is nothing to withdraw');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Not_Found, refused.getMessage(), 'The refusal says it is gone');
            }
            try {
                CommissionConfigService.draftFrom(null, 'CORRECTION', null);
                System.assert(false, 'There is nothing to copy');
            } catch (AuraHandledException refused) {
                System.assertEquals(Label.Commission_Service_Not_Found, refused.getMessage(), 'The refusal says it is gone');
            }
        }
        // Nothing to do without approved records
        CommissionConfigService.afterApproval(null);
        CommissionConfigService.afterApproval(new List<Commission_Config__c>());
    }
}