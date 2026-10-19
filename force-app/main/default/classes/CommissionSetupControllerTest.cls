// The Apex methods behind the Commission Setup screens: each one reaches its service, a message for the user comes
// through as it is, and anything unexpected is wrapped in the general error text.
@IsTest
private class CommissionSetupControllerTest {

    private static final Date TODAY = Date.today();

    private static User finance;
    private static User approver;

    private static void prepare() {
        CommissionTestData.useCatalog();
        finance = CommissionTestData.finance();
        approver = CommissionTestData.approver();
        CommissionAccess.reset();
    }

    // What the editor sends: the whole configuration as JSON, with what the screen added for itself
    private static String payloadOf(CommissionDto.Config config) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(config));
        body.put('dirty', true);
        body.put('savedAt', '10:42');
        return JSON.serialize(body);
    }

    @IsTest
    static void aDraftIsSavedSubmittedAndWithdrawn() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Controller Draft');
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Workspace space = CommissionSetupController.getWorkspace();
            System.assertEquals(true, space.flags.canConfigure, 'Finance configures');
            System.assertEquals(1, space.projects.size(), 'The active project is listed');
            System.assertEquals('NO_CONFIG', space.projects[0].state, 'It has no configuration yet');

            CommissionDto.Config blank = CommissionSetupController.newDraft(project.Id);
            System.assertEquals(project.Id, blank.projectId, 'A blank draft for the chosen project');
            System.assertEquals(null, blank.id, 'Nothing is stored yet');

            CommissionDto.SaveResult first = CommissionSetupController.saveConfig(
                payloadOf(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364))), 'DRAFT'
            );
            System.assertEquals(true, first.saved, 'The draft is saved. Issues: ' + JSON.serialize(first.issues));
            System.assertEquals(false, first.submitted, 'Save draft does not submit');
            System.assertEquals('Draft', first.config.status, 'It is a draft');

            CommissionDto.Config loaded = CommissionSetupController.getConfig(first.config.id);
            System.assertEquals(first.config.id, loaded.id, 'The saved draft can be loaded');
            System.assertEquals(true, loaded.canEdit, 'Finance can edit it');

            Test.startTest();
            CommissionDto.SaveResult second = CommissionSetupController.saveConfig(payloadOf(loaded), 'submit');
            System.assertEquals(true, second.submitted, 'Submit for approval submits. Issues: ' + JSON.serialize(second.issues));
            System.assertEquals('Pending Approval', second.config.status, 'It waits for the approver');

            CommissionDto.Config back = CommissionSetupController.withdraw(second.config.id);
            Test.stopTest();
            System.assertEquals('Draft', back.status, 'Withdrawn back to a draft');
            CommissionSetupController.discardDraft(back.id);
            System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c WHERE Id = :back.id], 'A withdrawn draft can be discarded');
        }
    }

    @IsTest
    static void theApproverDecidesAndFinanceStartsANewVersion() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Controller Decide');
        CommissionDto.SaveResult submitted;
        System.runAs(finance) {
            CommissionAccess.reset();
            submitted = CommissionSetupController.saveConfig(
                payloadOf(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364))), 'SUBMIT'
            );
            System.assertEquals(true, submitted.submitted, 'Submitted. Issues: ' + JSON.serialize(submitted.issues));
        }
        Test.startTest();
        System.runAs(approver) {
            CommissionAccess.reset();
            try {
                CommissionSetupController.decide(submitted.config.id, 'REJECT', null);
                System.assert(false, 'A rejection needs a comment');
            } catch (AuraHandledException refused) {
                System.assertEquals('Enter a comment to reject. Finance sees it with the returned draft.', refused.getMessage(), 'The message of the service comes through as it is');
            }
            CommissionDto.Config approved = CommissionSetupController.decide(submitted.config.id, 'APPROVE', 'Agreed');
            System.assertEquals('Approved', approved.status, 'The approver approved it');
        }
        Test.stopTest();
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.Config draft = CommissionSetupController.draftFrom(submitted.config.id, 'CORRECTION', null);
            System.assertEquals('Correction', draft.changeType, 'A new draft from the approved version');
            System.assertEquals(submitted.config.id, draft.supersedesId, 'It will replace the approved version');
            System.assertEquals(null, draft.id, 'Nothing is stored yet');
        }
    }

    @IsTest
    static void aDraftThatWasNeverSubmittedIsDiscarded() {
        prepare();
        Project__c project = CommissionTestData.project('Commission Controller Discard');
        System.runAs(finance) {
            CommissionAccess.reset();
            CommissionDto.SaveResult first = CommissionSetupController.saveConfig(
                payloadOf(CommissionTestData.validDraft(project.Id, TODAY, TODAY.addDays(364))), null
            );
            System.assertEquals(true, first.saved, 'Without an action the configuration is saved as a draft');
            System.assertEquals(false, first.submitted, 'Without an action nothing is submitted');
            Test.startTest();
            CommissionSetupController.discardDraft(first.config.id);
            Test.stopTest();
        }
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Config__c], 'The draft is gone');
    }

    @IsTest
    static void emptyInputsAndUnknownPropertiesAreAccepted() {
        CommissionDto.Config parsed = CommissionSetupController.parse(
            '{"id":"","projectId":null,"startDate":"2026-09-01","endDate":"","version":1,"dirty":true,'
                + '"baseline":{"name":"CC-0001"},"siblings":[{"name":"CC-0002"}],"approvers":[],'
                + '"stages":[{"key":"new-1","stageType":"Initial","triggerKey":"","triggerPercent":"","releasePercent":80,"open":true}],'
                + '"rates":[{"key":"r1","designation":"Sales_Advisor","paid":true,"currentRate":"","target":10,"id":""}]}'
        );
        System.assertEquals(null, parsed.id, 'An empty id is no id');
        System.assertEquals(Date.newInstance(2026, 9, 1), parsed.startDate, 'A date is read');
        System.assertEquals(null, parsed.endDate, 'An empty date is no date');
        System.assertEquals(null, parsed.baseline, 'What a save never reads is left out');
        System.assertEquals(1, parsed.stages.size(), 'The stages are read');
        System.assertEquals(null, parsed.stages[0].triggerKey, 'An empty text is no value');
        System.assertEquals(null, parsed.stages[0].triggerPercent, 'An empty number is no value');
        System.assertEquals(80, parsed.stages[0].releasePercent.intValue(), 'A number is read');
        System.assertEquals(null, parsed.rates[0].currentRate, 'An empty rate is no value');
        System.assertEquals(true, parsed.rates[0].paid, 'A switch is read');
    }

    @IsTest
    static void messagesReachTheScreen() {
        prepare();
        User outsider = CommissionTestData.outsider();
        CommissionAccess.reset();
        System.runAs(outsider) {
            CommissionAccess.reset();
            CommissionDto.Workspace space = CommissionSetupController.getWorkspace();
            System.assertEquals(false, space.flags.canView, 'Somebody without access gets the flags only');
            System.assertEquals(0, space.projects.size(), 'And no projects');
            try {
                CommissionSetupController.newDraft(null);
                System.assert(false, 'Somebody without access cannot start a draft');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
        }
        System.runAs(finance) {
            CommissionAccess.reset();
            try {
                CommissionSetupController.getConfig(null);
                System.assert(false, 'There is nothing to load');
            } catch (AuraHandledException refused) {
                System.assertEquals('This configuration no longer exists. Go back to the overview.', refused.getMessage(), 'The message of the service comes through as it is');
            }
            try {
                CommissionSetupController.saveConfig('', 'DRAFT');
                System.assert(false, 'There is nothing to save');
            } catch (AuraHandledException refused) {
                System.assertEquals(CommissionSetupController.COMMISSION_SERVICE_NOTHING_TO_SAVE, refused.getMessage(), 'The message of the service comes through as it is');
            }
            try {
                CommissionSetupController.saveConfig('[1, 2]', 'DRAFT');
                System.assert(false, 'A list is not a configuration');
            } catch (AuraHandledException refused) {
                System.assertEquals(CommissionSetupController.COMMISSION_SERVICE_NOTHING_TO_SAVE, refused.getMessage(), 'The message of the service comes through as it is');
            }
            // Something the code did not expect: the general text, followed by the cause
            try {
                CommissionSetupController.saveConfig('{ this is not JSON', 'DRAFT');
                System.assert(false, 'Broken input cannot be saved');
            } catch (AuraHandledException refused) {
                System.assert(refused.getMessage().startsWith(CommissionSetupController.COMMISSION_COMMON_ERROR), 'The general text comes first: ' + refused.getMessage());
            }
            try {
                CommissionSetupController.draftFrom(null, 'NOTHING', null);
                System.assert(false, 'Only the five choices exist');
            } catch (AuraHandledException refused) {
                System.assertEquals('This kind of change is not known. Reload the page and try again.', refused.getMessage(), 'The message of the service comes through as it is');
            }
            try {
                CommissionSetupController.withdraw(null);
                System.assert(false, 'There is nothing to withdraw');
            } catch (AuraHandledException refused) {
                System.assertEquals('This configuration no longer exists. Go back to the overview.', refused.getMessage(), 'The message of the service comes through as it is');
            }
            try {
                CommissionSetupController.discardDraft(null);
                System.assert(false, 'There is nothing to discard');
            } catch (AuraHandledException refused) {
                System.assertEquals('This configuration no longer exists. Go back to the overview.', refused.getMessage(), 'The message of the service comes through as it is');
            }
            try {
                CommissionSetupController.decide(null, 'APPROVE', null);
                System.assert(false, 'Finance does not decide');
            } catch (AuraHandledException refused) {
                System.assert(String.isNotBlank(refused.getMessage()), 'The refusal says why');
            }
        }
    }
}