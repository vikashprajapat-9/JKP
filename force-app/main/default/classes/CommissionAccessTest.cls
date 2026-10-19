@IsTest
private class CommissionAccessTest {

    private static Set<Id> idsOf(List<User> users) {
        return new Map<Id, User>(users).keySet();
    }

    private static String refusalOf(String capability) {
        try {
            CommissionAccess.require(capability);
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
        return null;
    }

    @IsTest
    static void capabilitiesFollowTheRolesOfTheSetting() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User approver = CommissionTestData.approver();
        User headOfSales = CommissionTestData.headOfSales();
        User advisor = CommissionTestData.advisor();
        User outsider = CommissionTestData.outsider();

        System.assert(CommissionAccess.can(CommissionAccess.CONFIGURE, finance.Id), 'Finance configures');
        System.assert(CommissionAccess.can(CommissionAccess.VIEW, finance.Id), 'Whoever configures can read');
        System.assert(CommissionAccess.can(CommissionAccess.ALERT, finance.Id), 'The alert role of the test setting is the Finance role');
        System.assert(!CommissionAccess.can(CommissionAccess.APPROVE, finance.Id), 'Finance does not approve');
        System.assert(!CommissionAccess.can(CommissionAccess.TARGETS, finance.Id), 'Finance does not maintain targets');

        System.assert(CommissionAccess.can(CommissionAccess.APPROVE, approver.Id), 'The approver approves');
        System.assert(CommissionAccess.can(CommissionAccess.VIEW, approver.Id), 'Whoever approves can read');
        System.assert(!CommissionAccess.can(CommissionAccess.CONFIGURE, approver.Id), 'The approver does not configure');

        System.assert(CommissionAccess.can(CommissionAccess.TARGETS, headOfSales.Id), 'The Head of Sales maintains targets');
        System.assert(CommissionAccess.can(CommissionAccess.VIEW, headOfSales.Id), 'Whoever maintains targets can read');

        for (String capability : new List<String>{ CommissionAccess.CONFIGURE, CommissionAccess.APPROVE, CommissionAccess.TARGETS, CommissionAccess.VIEW, CommissionAccess.ALERT }) {
            System.assert(!CommissionAccess.can(capability, outsider.Id), 'An outsider has no capability: ' + capability);
        }
        System.assert(!CommissionAccess.can('SOMETHING_ELSE', finance.Id), 'An unknown capability is never held');
        System.assert(!CommissionAccess.can(CommissionAccess.CONFIGURE, null), 'Nobody holds nothing');

        System.assert(CommissionAccess.isPayee(advisor.Id), 'The advisor holds the role of a designation');
        System.assert(!CommissionAccess.isPayee(outsider.Id), 'The outsider is not paid');
        System.assert(!CommissionAccess.selfApprovalAllowed(approver.Id), 'Self-approval is off in the test setting');
    }

    @IsTest
    static void flagsAndRequireSpeakForTheRunningUser() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User advisor = CommissionTestData.advisor();
        User outsider = CommissionTestData.outsider();

        System.runAs(finance) {
            CommissionDto.Flags flags = CommissionAccess.flags();
            System.assertEquals(true, flags.canConfigure, 'Finance configures');
            System.assertEquals(false, flags.canApprove, 'Finance does not approve');
            System.assertEquals(false, flags.canManageTargets, 'Finance does not maintain targets');
            System.assertEquals(true, flags.canView, 'Finance reads');
            System.assertEquals(false, flags.isPayee, 'Finance is not paid');
            System.assertEquals(finance.Id, flags.userId, 'The flags are those of the running user');
            System.assert(CommissionAccess.can(CommissionAccess.CONFIGURE), 'The running user is asked');
            System.assertEquals(null, refusalOf(CommissionAccess.CONFIGURE), 'Finance may configure');
            System.assertEquals(CommissionAccess.COMMISSION_RULE_APPROVE_ONLY, refusalOf(CommissionAccess.APPROVE), 'Finance is told who approves');
            System.assert(CommissionAccess.seesEveryone(), 'A reader without targets is not limited to a reporting line');
        }
        System.runAs(advisor) {
            System.assert(CommissionAccess.isPayee(), 'The advisor sees their own terms');
            System.assertEquals(true, CommissionAccess.flags().isPayee, 'The flag says so');
            System.assert(!CommissionAccess.seesEveryone(), 'A payee does not see everyone');
        }
        System.runAs(outsider) {
            System.assertEquals(CommissionAccess.COMMISSION_COMMON_NO_ACCESS, refusalOf(CommissionAccess.VIEW), 'No access for an outsider');
            System.assertEquals(CommissionAccess.COMMISSION_RULE_CONFIGURE_ONLY, refusalOf(CommissionAccess.CONFIGURE), 'Only Finance configures');
            System.assertEquals(CommissionAccess.COMMISSION_RULE_TARGETS_ONLY, refusalOf(CommissionAccess.TARGETS), 'Targets are refused');
            System.assertEquals(false, CommissionAccess.flags().canView, 'The outsider cannot read');
        }
    }

    @IsTest
    static void profileListsGiveCapabilitiesToo() {
        CommissionTestData.useCatalog();
        User outsider = CommissionTestData.outsider();
        User headOfSales = CommissionTestData.headOfSales();
        String profileName = outsider.Profile.Name;

        System.runAs(headOfSales) {
            System.assert(!CommissionAccess.seesEveryone(), 'A Head of Sales is limited to the reporting line');
        }

        CommissionTestData.setSetting(new Map<String, Object>{
            'View_Profiles__c' => 'No Such Profile; ' + profileName.toUpperCase(), 'Self_Approval_Profiles__c' => profileName
        });
        System.assert(CommissionAccess.can(CommissionAccess.VIEW, outsider.Id), 'A profile in the list reads');
        System.assert(CommissionAccess.selfApprovalAllowed(outsider.Id), 'A profile in the self-approval list may approve its own entry');
        System.runAs(outsider) {
            System.assert(CommissionAccess.selfApprovalAllowed(), 'The running user is asked');
            System.assert(CommissionAccess.seesEveryone(), 'A reader without targets sees everyone');
        }

        CommissionTestData.setSetting(new Map<String, Object>{
            'View_Profiles__c' => null, 'Self_Approval_Profiles__c' => null, 'Target_Profiles__c' => profileName
        });
        System.runAs(outsider) {
            System.assert(CommissionAccess.can(CommissionAccess.TARGETS), 'A profile in the target list maintains targets');
            System.assert(CommissionAccess.seesEveryone(), 'A target profile is not limited to a reporting line');
            System.assert(!CommissionAccess.selfApprovalAllowed(), 'Self-approval is off again');
        }
        System.assert(idsOf(CommissionAccess.usersWho(CommissionAccess.TARGETS)).contains(outsider.Id), 'Users are found by profile as well');
    }

    @IsTest
    static void usersAreFoundByCapabilityAndByRole() {
        CommissionTestData.useCatalog();
        User finance = CommissionTestData.finance();
        User secondFinance = CommissionTestData.secondFinance();
        User approver = CommissionTestData.approver();
        User headOfSales = CommissionTestData.headOfSales();
        User seniorManager = CommissionTestData.seniorManager();
        User advisor = CommissionTestData.advisor();
        User outsider = CommissionTestData.outsider();

        Set<Id> configure = idsOf(CommissionAccess.usersWho(CommissionAccess.CONFIGURE));
        System.assertEquals(new Set<Id>{ finance.Id, secondFinance.Id }, configure, 'Both Finance users configure, nobody else');
        System.assertEquals(new Set<Id>{ approver.Id }, idsOf(CommissionAccess.usersWho(CommissionAccess.APPROVE)), 'One approver');
        System.assertEquals(new Set<Id>{ headOfSales.Id }, idsOf(CommissionAccess.usersWho(CommissionAccess.TARGETS)), 'One Head of Sales');
        System.assertEquals(new Set<Id>{ finance.Id, secondFinance.Id }, idsOf(CommissionAccess.usersWho(CommissionAccess.ALERT)), 'Alerts go to the Finance role');
        Set<Id> readers = idsOf(CommissionAccess.usersWho(CommissionAccess.VIEW));
        System.assert(readers.containsAll(new Set<Id>{ finance.Id, approver.Id, headOfSales.Id }), 'Everyone with a capability reads');
        System.assert(!readers.contains(outsider.Id), 'The outsider does not read');
        System.assertEquals(0, CommissionAccess.usersWho('SOMETHING_ELSE').size(), 'An unknown capability has no users');

        Set<Id> byRole = idsOf(CommissionAccess.usersInRoles(new Set<String>{ CommissionTestData.ROLE_ADVISOR.toUpperCase(), ' ' + CommissionTestData.ROLE_SM.toLowerCase() + ' ', '' }));
        System.assertEquals(new Set<Id>{ advisor.Id, seniorManager.Id }, byRole, 'Users are found by role, whatever the case');
        System.assertEquals(0, CommissionAccess.usersInRoles(null).size(), 'No roles, no users');
        System.assertEquals(0, CommissionAccess.usersInRoles(new Set<String>{ ' ' }).size(), 'Blank roles, no users');
    }

    @IsTest
    static void reportingLineFollowsTheManagers() {
        CommissionTestData.useCatalog();
        User headOfSales = CommissionTestData.headOfSales();
        User seniorManager = CommissionTestData.seniorManager();
        User advisor = CommissionTestData.advisor();
        User outsider = CommissionTestData.outsider();

        Set<Id> below = CommissionAccess.reportingLine(headOfSales.Id);
        System.assert(below.contains(seniorManager.Id), 'The senior manager reports to the Head of Sales');
        System.assert(below.contains(advisor.Id), 'The advisor reports to the Head of Sales through the senior manager');
        System.assert(!below.contains(headOfSales.Id), 'The user is not part of their own line');
        System.assert(!below.contains(outsider.Id), 'The outsider reports to nobody here');

        Set<Id> team = CommissionAccess.reportingLine(seniorManager.Id);
        System.assert(team.contains(advisor.Id), 'The advisor reports to the senior manager');
        System.assert(!team.contains(headOfSales.Id), 'A line only goes down');
        System.assert(!CommissionAccess.reportingLine(advisor.Id).contains(seniorManager.Id), 'Nobody reports to the advisor');
        System.assertEquals(0, CommissionAccess.reportingLine(null).size(), 'No user, no line');

        // The answer is remembered; the caller gets a copy it may change
        below.clear();
        System.assert(CommissionAccess.reportingLine(headOfSales.Id).contains(advisor.Id), 'A second call gives the same line');
    }
}