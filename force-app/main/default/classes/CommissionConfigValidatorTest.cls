@IsTest
private class CommissionConfigValidatorTest {

    private static final Date START_DAY = Date.today().addDays(30);
    private static final Date END_DAY = Date.today().addDays(394);

    // A complete draft on a new project
    private static CommissionDto.Config draft() {
        CommissionTestData.useCatalog();
        Project__c project = CommissionTestData.project('Validator Towers');
        return CommissionTestData.validDraft(project.Id, START_DAY, END_DAY);
    }

    private static Set<String> codesOf(List<CommissionDto.Issue> issues) {
        Set<String> codes = new Set<String>();
        for (CommissionDto.Issue issue : issues) {
            codes.add(issue.code);
        }
        return codes;
    }

    private static CommissionDto.Issue issueOf(List<CommissionDto.Issue> issues, String code) {
        for (CommissionDto.Issue issue : issues) {
            if (issue.code == code) {
                return issue;
            }
        }
        return null;
    }

    private static String textOf(List<CommissionDto.Issue> issues) {
        List<String> lines = new List<String>();
        for (CommissionDto.Issue issue : issues) {
            lines.add(issue.code + ' [' + issue.section + '] ' + issue.message);
        }
        return String.join(lines, ' | ');
    }

    private static CommissionDto.Stage stageOf(CommissionDto.Config config, String stageType, String designation) {
        for (CommissionDto.Stage stage : config.stages) {
            if (stage.stageType == stageType && (designation == null ? String.isBlank(stage.designation) : stage.designation == designation)) {
                return stage;
            }
        }
        return null;
    }

    private static void removeStage(CommissionDto.Config config, String stageType, String designation) {
        CommissionDto.Stage gone = stageOf(config, stageType, designation);
        config.stages.remove(config.stages.indexOf(gone));
    }

    private static CommissionDto.Rate rateOf(CommissionDto.Config config, String designation) {
        for (CommissionDto.Rate rate : config.rates) {
            if (rate.designation == designation) {
                return rate;
            }
        }
        return null;
    }

    private static CommissionDto.Stage newStage(String key, String stageType, Integer sequence, String triggerKey, Decimal releasePercent, String designation) {
        CommissionDto.Stage stage = new CommissionDto.Stage();
        stage.key = key;
        stage.stageType = stageType;
        stage.sequence = sequence;
        stage.triggerKey = triggerKey;
        stage.releasePercent = releasePercent;
        stage.designation = designation;
        return stage;
    }

    @IsTest
    static void aCompleteDraftHasNoIssues() {
        CommissionDto.Config config = draft();
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(0, issues.size(), 'The valid draft can be submitted: ' + textOf(issues));
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'The valid draft can be saved');
        System.assertEquals(0, CommissionConfigValidator.check(null, true).size(), 'Nothing to check');

        // The records a save keeps: three shared stages, the two of CP External and the fixed one of the referral fee
        System.assertEquals(6, CommissionConfigValidator.stagesOf(config).size(), 'Stage rows of the draft');
        System.assertEquals(7, CommissionConfigValidator.ratesOf(config).size(), 'Rate rows of the draft');
        System.assertEquals('Draft', CommissionConfigValidator.headerOf(config).Status__c, 'The header of a draft');
    }

    @IsTest
    static void anEmptyDraftCanBeSavedButNotSubmitted() {
        CommissionDto.Config config = draft();
        config.stages = new List<CommissionDto.Stage>();
        for (CommissionDto.Rate rate : config.rates) {
            rate.paid = false;
        }
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'An unfinished draft can be saved');

        Set<String> codes = codesOf(CommissionConfigValidator.check(config, true));
        System.assert(codes.contains('STAGE_INITIAL_REQUIRED'), 'The Initial stage is required: ' + codes);
        System.assert(codes.contains('STAGE_FINAL_REQUIRED'), 'The Final stage is required by the setting: ' + codes);
        System.assert(codes.contains('RATES_NONE'), 'Somebody must be paid: ' + codes);
        System.assert(!codes.contains('STAGES_TOTAL'), 'No total without stages: ' + codes);

        CommissionTestData.setSetting(new Map<String, Object>{ 'Final_Stage_Required__c' => false });
        codes = codesOf(CommissionConfigValidator.check(config, true));
        System.assert(!codes.contains('STAGE_FINAL_REQUIRED'), 'The setting switches the Final stage rule off: ' + codes);
    }

    @IsTest
    static void thePeriodMustBeGivenAndInOrder() {
        CommissionDto.Config config = draft();
        Id projectId = config.projectId;
        config.projectId = null;
        config.startDate = null;
        config.endDate = null;
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(3, issues.size(), 'Project, start and end are missing: ' + textOf(issues));
        for (CommissionDto.Issue issue : issues) {
            System.assertEquals('PERIOD_REQUIRED', issue.code, 'Each missing value is reported');
            System.assertEquals('period', issue.section, 'In the period section');
        }

        config.projectId = projectId;
        config.startDate = END_DAY;
        config.endDate = START_DAY;
        issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'PERIOD_ORDER' }, codesOf(issues), 'The end lies before the start: ' + textOf(issues));

        // Records without anything do not break the check
        issues = CommissionConfigValidator.checkRecords(null, null, null, false);
        System.assertEquals(new Set<String>{ 'PERIOD_REQUIRED' }, codesOf(issues), 'An empty header misses its period');
    }

    @IsTest
    static void anOverlapNamesTheOtherConfiguration() {
        CommissionDto.Config config = draft();
        Commission_Config__c inForce = CommissionTestData.insertApproved(config.projectId, START_DAY, END_DAY);

        config.startDate = START_DAY.addDays(10);
        config.endDate = END_DAY.addDays(10);
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, false);
        CommissionDto.Issue overlap = issueOf(issues, 'PERIOD_OVERLAP');
        System.assertNotEquals(null, overlap, 'The overlap is found: ' + textOf(issues));
        System.assert(overlap.message.contains(inForce.Name), 'The message names the other configuration: ' + overlap.message);

        CommissionDto.Summary clash = CommissionConfigValidator.overlapWith(CommissionConfigValidator.headerOf(config));
        System.assertEquals(inForce.Id, clash.id, 'The clash is the approved configuration');
        System.assertEquals(1, clash.version, 'With its version');
        System.assertEquals('UPCOMING', clash.state, 'It starts in the future');
        System.assertEquals(overlap.message, CommissionConfigValidator.overlapMessage(clash), 'One message for the screen and the trigger');
        System.assertEquals(null, CommissionConfigValidator.overlapMessage(null), 'No clash, no message');

        // The day after the other period ends is free
        config.startDate = END_DAY.addDays(1);
        config.endDate = END_DAY.addDays(100);
        System.assertEquals(null, CommissionConfigValidator.overlapWith(CommissionConfigValidator.headerOf(config)), 'Periods that touch do not overlap');

        // A correction replaces the version it was made from, so that version is ignored
        config.startDate = START_DAY;
        config.endDate = END_DAY;
        config.changeType = 'Correction';
        config.supersedesId = inForce.Id;
        System.assertEquals(null, CommissionConfigValidator.overlapWith(CommissionConfigValidator.headerOf(config)), 'The corrected version is ignored');

        // Another project is never a clash; a header without a period has nothing to compare
        Project__c other = CommissionTestData.project('Validator Gardens');
        config.changeType = 'New';
        config.supersedesId = null;
        config.projectId = other.Id;
        System.assertEquals(null, CommissionConfigValidator.overlapWith(CommissionConfigValidator.headerOf(config)), 'Another project');
        System.assertEquals(null, CommissionConfigValidator.overlapWith(new Commission_Config__c()), 'No period');
        System.assertEquals(null, CommissionConfigValidator.overlapWith(null), 'No header');
    }

    @IsTest
    static void thePeriodMustFitTheVersionItComesFrom() {
        CommissionDto.Config config = draft();
        Date today = Date.today();
        Commission_Config__c inForce = CommissionTestData.insertApproved(config.projectId, today.addDays(-30), today.addDays(300));

        // Change terms from a date: after the start of the earlier version, not after its end
        config.changeType = 'Change From Date';
        config.supersedesId = inForce.Id;
        config.startDate = today.addDays(-30);
        config.endDate = today.addDays(300);
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'PERIOD_SOURCE' }, codesOf(issues), 'The start must be later than the earlier start: ' + textOf(issues));
        config.startDate = today.addDays(1);
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'A start inside the earlier period is fine');

        // End early: not after the end of the period
        config.changeType = 'End Early';
        config.startDate = today.addDays(-30);
        config.endDate = today.addDays(301);
        issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'PERIOD_SOURCE' }, codesOf(issues), 'The end cannot move out: ' + textOf(issues));
        config.endDate = today;
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'An earlier end is fine');

        // Next period: follows an approved period of the project
        config.changeType = 'Next Period';
        config.supersedesId = null;
        config.startDate = today.addDays(301);
        config.endDate = today.addDays(600);
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'The day after the period ends');
        config.startDate = today.addDays(-400);
        config.endDate = today.addDays(-100);
        issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'PERIOD_SOURCE' }, codesOf(issues), 'A next period cannot lie before every approved period: ' + textOf(issues));

        // A change needs its reason when it is submitted
        config.startDate = today.addDays(301);
        config.endDate = today.addDays(600);
        issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(new Set<String>{ 'REASON_REQUIRED' }, codesOf(issues), 'Only the reason is missing: ' + textOf(issues));
        System.assertEquals('options', issues[0].section, 'The reason is in the options section');
        config.changeReason = 'Rates for the new year';
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'With a reason it can be submitted');
    }

    @IsTest
    static void aChangeCannotReachBackBeforeToday() {
        CommissionDto.Config config = draft();
        Date today = Date.today();
        Commission_Config__c inForce = CommissionTestData.insertApproved(config.projectId, today.addDays(-30), today.addDays(300));
        config.supersedesId = inForce.Id;
        config.changeReason = 'New terms agreed';

        // Change terms from a date: yesterday lies inside the earlier period, so the draft can be kept
        config.changeType = 'Change From Date';
        config.startDate = today.addDays(-1);
        config.endDate = today.addDays(300);
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'A draft with a passed start can still be saved');
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(1, issues.size(), 'Only the passed start stops the submission: ' + textOf(issues));
        System.assertEquals('PERIOD_SOURCE', issues[0].code, 'The start has passed');
        System.assertEquals('period', issues[0].section, 'In the period section');
        System.assertEquals('startDate', issues[0].field, 'On the start date');
        System.assertEquals(CommissionConfigValidator.fill(CommissionConfigValidator.COMMISSION_RULE_START_IN_PAST, new List<Object>{ today.addDays(-1) }),
            issues[0].message, 'The message names the date');
        config.startDate = today;
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'A change can start today');

        // End early: the same for the new end
        config.changeType = 'End Early';
        config.startDate = today.addDays(-30);
        config.endDate = today.addDays(-1);
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'A draft with a passed end can still be saved');
        issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(1, issues.size(), 'Only the passed end stops the submission: ' + textOf(issues));
        System.assertEquals('PERIOD_SOURCE', issues[0].code, 'The end has passed');
        System.assertEquals('endDate', issues[0].field, 'On the end date');
        System.assertEquals(CommissionConfigValidator.fill(CommissionConfigValidator.COMMISSION_RULE_END_IN_PAST, new List<Object>{ today.addDays(-1) }),
            issues[0].message, 'The message names the date');
        config.endDate = today;
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'A period can end today');
    }

    @IsTest
    static void stageRulesThatAlwaysApply() {
        CommissionDto.Config config = draft();
        CommissionDto.Stage initial = stageOf(config, 'Initial', null);
        CommissionDto.Stage mid = stageOf(config, 'Mid', null);

        initial.triggerKey = 'No_Such_Event';
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'STAGE_TRIGGER_INVALID' }, codesOf(issues), 'An unknown payout event: ' + textOf(issues));
        System.assertEquals('stages', issues[0].section, 'A shared stage is in the stages section');
        System.assertEquals(initial.key, issues[0].rowKey, 'The issue names the row of the screen');
        System.assertEquals('triggerKey', issues[0].field, 'And the field');

        initial.triggerKey = 'Handover';
        issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'STAGE_TRIGGER_INVALID' }, codesOf(issues), 'A Final event on the Initial stage: ' + textOf(issues));
        initial.triggerKey = 'SPA_Signing';

        initial.releasePercent = 0;
        mid.triggerPercent = 150;
        issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'STAGE_PERCENT_RANGE' }, codesOf(issues), 'Percentages out of range: ' + textOf(issues));
        System.assertEquals(2, issues.size(), 'Both are reported');
        initial.releasePercent = 80;

        mid.triggerKey = 'Tranche_Paid';
        mid.triggerPercent = null;
        mid.triggerTranche = 0;
        issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'STAGE_PERCENT_RANGE' }, codesOf(issues), 'A tranche number below 1: ' + textOf(issues));
        mid.triggerKey = 'Percent_Of_Price_Paid';
        mid.triggerTranche = null;
        mid.triggerPercent = 50;

        config.stages.add(newStage('second-initial', 'Initial', 4, 'SPA_Signing', null, null));
        config.stages.add(newStage('second-final', 'Final', 5, 'Handover', null, null));
        config.stages.add(newStage('own-mid', 'Mid', 3, 'Percent_Of_Price_Paid', null, 'CP_External'));
        issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'STAGE_DUPLICATE', 'STAGE_MID_NOT_ALLOWED' }, codesOf(issues), 'Duplicates and a Mid in an own release: ' + textOf(issues));
        System.assertEquals('own:CP_External', issueOf(issues, 'STAGE_MID_NOT_ALLOWED').section, 'An own release has its own section');
    }

    @IsTest
    static void stageRulesForSubmitting() {
        CommissionDto.Config config = draft();
        CommissionDto.Stage initial = stageOf(config, 'Initial', null);
        CommissionDto.Stage mid = stageOf(config, 'Mid', null);
        CommissionDto.Stage finalStage = stageOf(config, 'Final', null);

        initial.triggerKey = null;
        mid.triggerPercent = null;
        finalStage.releasePercent = null;
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'A draft may still miss these');
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(new Set<String>{ 'STAGE_TRIGGER_REQUIRED', 'STAGE_PARAMETER_REQUIRED', 'STAGE_PERCENT_REQUIRED', 'STAGES_TOTAL' },
            codesOf(issues), 'What is missing is listed: ' + textOf(issues));
        System.assert(issueOf(issues, 'STAGES_TOTAL').message.contains('90'), 'The message carries the total: ' + issueOf(issues, 'STAGES_TOTAL').message);
        initial.triggerKey = 'SPA_Signing';
        finalStage.releasePercent = 10;

        mid.triggerKey = 'Tranche_Paid';
        System.assertEquals(new Set<String>{ 'STAGE_PARAMETER_REQUIRED' }, codesOf(CommissionConfigValidator.check(config, true)), 'The tranche number is needed');
        mid.triggerKey = 'Installment_Paid';
        System.assertEquals(new Set<String>{ 'STAGE_PARAMETER_REQUIRED' }, codesOf(CommissionConfigValidator.check(config, true)), 'The instalment is needed');
        mid.triggerKey = 'Percent_Of_Price_Paid';
        mid.triggerPercent = 50;

        // A second Mid payout at a lower percentage paid than the one before it
        CommissionDto.Stage secondMid = newStage('second-mid', 'Mid', 3, 'Percent_Of_Price_Paid', 5, null);
        secondMid.triggerPercent = 40;
        finalStage.sequence = 4;
        finalStage.releasePercent = 5;
        config.stages.add(secondMid);
        issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(new Set<String>{ 'STAGE_MID_ORDER' }, codesOf(issues), 'Mid payouts must rise: ' + textOf(issues));
        System.assertEquals('second-mid', issues[0].rowKey, 'The later row is the one to correct');
        secondMid.triggerPercent = 75;
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'In rising order it is fine');

        removeStage(config, 'Initial', null);
        Set<String> codes = codesOf(CommissionConfigValidator.check(config, true));
        System.assert(codes.contains('STAGE_INITIAL_REQUIRED') && codes.contains('STAGES_TOTAL'), 'Without the Initial stage: ' + codes);
    }

    @IsTest
    static void aDesignationWithItsOwnRelease() {
        CommissionDto.Config config = draft();
        CommissionDto.Rate external = rateOf(config, 'CP_External');
        CommissionDto.Stage ownFinal = stageOf(config, 'Final', 'CP_External');

        ownFinal.releasePercent = 10;
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(new Set<String>{ 'OWN_TOTAL' }, codesOf(issues), 'The own release must total 100: ' + textOf(issues));
        System.assertEquals('own:CP_External', issues[0].section, 'In the section of the designation');
        System.assert(issues[0].message.contains('90'), 'The message carries the total: ' + issues[0].message);
        ownFinal.releasePercent = 20;

        external.releaseMode = null;
        issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(new Set<String>{ 'OWN_RELEASE_REQUIRED' }, codesOf(issues), 'The way of release must be chosen: ' + textOf(issues));
        System.assertEquals(external.key, issues[0].rowKey, 'The issue names the rate');

        // Everything at the Initial event: only the Initial row counts, at 100
        external.releaseMode = 'All At Initial';
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'One Initial row is enough');
        Integer ownRows = 0;
        for (Commission_Stage__c row : CommissionConfigValidator.stagesOf(config)) {
            if (row.Designation__c == 'CP_External') {
                ownRows++;
                System.assert(row.Release_Percent__c == 100, 'Released completely at the Initial event: ' + row.Release_Percent__c);
            }
        }
        System.assertEquals(1, ownRows, 'The Final row is dropped');

        removeStage(config, 'Initial', 'CP_External');
        System.assertEquals(new Set<String>{ 'OWN_RELEASE_REQUIRED' }, codesOf(CommissionConfigValidator.check(config, true)), 'The Initial row is missing');

        external.releaseMode = 'Split';
        System.assertEquals(new Set<String>{ 'OWN_RELEASE_REQUIRED', 'OWN_TOTAL' }, codesOf(CommissionConfigValidator.check(config, true)), 'A split needs both rows');

        // A designation that is not paid needs nothing
        external.paid = false;
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'Not paid, not checked');
    }

    @IsTest
    static void rateRules() {
        CommissionDto.Config config = draft();
        CommissionDto.Rate advisor = rateOf(config, 'Sales_Advisor');
        CommissionDto.Rate referrer = rateOf(config, 'Referrer');
        CommissionDto.Rate partner = rateOf(config, 'CP_Internal');

        advisor.currentRate = 150;
        advisor.exceedRate = 120;
        advisor.target = -1;
        referrer.flatAmount = -5;
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, false);
        System.assertEquals(new Set<String>{ 'RATE_RANGE', 'EXCEED_LOWER' }, codesOf(issues), 'Values out of range: ' + textOf(issues));
        System.assertEquals(5, issues.size(), 'Current, exceed, target, amount and the lower exceed rate: ' + textOf(issues));
        Set<String> sections = new Set<String>();
        for (CommissionDto.Issue issue : issues) {
            sections.add(issue.section);
        }
        System.assertEquals(new Set<String>{ 'rates', 'fee:Referrer' }, sections, 'A flat fee has its own section');

        advisor.currentRate = null;
        advisor.exceedRate = null;
        advisor.target = null;
        referrer.flatAmount = 0;
        partner.exceedRate = null;
        partner.targetBasis = null;
        partner.targetPeriod = null;
        partner.exceedMode = null;
        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'A draft may still miss these');
        issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(new Set<String>{ 'RATE_REQUIRED', 'TARGET_REQUIRED', 'EXCEED_REQUIRED', 'TARGET_OPTIONS_REQUIRED' }, codesOf(issues),
            'What is missing is listed: ' + textOf(issues));
        Integer options = 0;
        Integer required = 0;
        for (CommissionDto.Issue issue : issues) {
            options += issue.code == 'TARGET_OPTIONS_REQUIRED' ? 1 : 0;
            required += issue.code == 'RATE_REQUIRED' ? 1 : 0;
        }
        System.assertEquals(3, options, 'Basis, period and exceed mode are reported once each');
        System.assertEquals(2, required, 'The Current rate of the advisor and the amount of the referral fee');
        System.assertEquals(advisor.key, issueOf(issues, 'TARGET_REQUIRED').rowKey, 'The issue names the row of the screen');

        // A Current rate of 0 % is a rate; an optional target may stay empty
        advisor.currentRate = 0;
        advisor.exceedRate = 1;
        advisor.target = 10;
        referrer.flatAmount = 500000;
        partner.target = null;
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'Complete again');
    }

    @IsTest
    static void aDesignationHasOneRate() {
        CommissionDto.Config config = draft();
        CommissionDto.Rate advisor = rateOf(config, 'Sales_Advisor');
        CommissionDto.Rate second = new CommissionDto.Rate();
        second.key = 'rate-second-advisor';
        second.designation = advisor.designation;
        second.paid = true;
        second.currentRate = advisor.currentRate;
        second.exceedRate = advisor.exceedRate;
        second.target = advisor.target;
        second.targetBasis = advisor.targetBasis;
        second.targetPeriod = advisor.targetPeriod;
        second.exceedMode = advisor.exceedMode;
        config.rates.add(second);

        System.assertEquals(0, CommissionConfigValidator.check(config, false).size(), 'A draft can still be saved');
        List<CommissionDto.Issue> issues = CommissionConfigValidator.check(config, true);
        System.assertEquals(1, issues.size(), 'The second rate of the advisor is reported once: ' + textOf(issues));
        System.assertEquals('RATE_DUPLICATE', issues[0].code, 'Two rates for one designation');
        System.assertEquals('rates', issues[0].section, 'In the rates section');
        System.assertEquals(second.key, issues[0].rowKey, 'The later row is the one too many');
        System.assert(issues[0].message.contains('Sales Advisor'), 'The message names the designation: ' + issues[0].message);

        // A designation that is switched off has no row
        second.paid = false;
        System.assertEquals(0, CommissionConfigValidator.check(config, true).size(), 'Not paid, not counted');

        // Saved records: only active rows count
        Commission_Config__c saved = CommissionTestData.insertApproved(config.projectId, START_DAY, END_DAY);
        List<Commission_Stage__c> stages = CommissionTestData.stagesOf(saved.Id);
        List<Commission_Rate__c> rates = CommissionTestData.ratesOf(saved.Id);
        Commission_Rate__c twin = rates[0].clone(false, true);
        rates.add(twin);
        System.assertEquals(0, CommissionConfigValidator.checkRecords(saved, stages, rates, false).size(), 'Not looked at before the submission');
        issues = CommissionConfigValidator.checkRecords(saved, stages, rates, true);
        System.assertEquals(new Set<String>{ 'RATE_DUPLICATE' }, codesOf(issues), 'Two active rows of one designation: ' + textOf(issues));
        System.assertEquals(1, issues.size(), 'Reported once');
        twin.Active__c = false;
        System.assertEquals(0, CommissionConfigValidator.checkRecords(saved, stages, rates, true).size(), 'A switched-off row is not there');
    }

    @IsTest
    static void savedRecordsAreCheckedByTheSameRules() {
        CommissionDto.Config config = draft();
        Commission_Config__c saved = CommissionTestData.insertApproved(config.projectId, START_DAY, END_DAY);
        List<Commission_Stage__c> stages = CommissionTestData.stagesOf(saved.Id);
        List<Commission_Rate__c> rates = CommissionTestData.ratesOf(saved.Id);
        System.assertEquals(6, stages.size(), 'Three shared stages, two of CP External, one of the referral fee');
        System.assertEquals(7, rates.size(), 'Seven designations are paid');

        List<CommissionDto.Issue> issues = CommissionConfigValidator.checkRecords(saved, stages, rates, true);
        System.assertEquals(0, issues.size(), 'The saved configuration is complete: ' + textOf(issues));

        // A payout event that has left the catalog stays valid on the row that used it, but not on a new row
        List<Commission_Trigger__mdt> kept = new List<Commission_Trigger__mdt>();
        for (Commission_Trigger__mdt event : CommissionCatalog.testTriggers) {
            if (event.DeveloperName != 'Handover') {
                kept.add(event);
            }
        }
        CommissionCatalog.testTriggers = kept;
        issues = CommissionConfigValidator.checkRecords(saved, stages, rates, true);
        System.assertEquals(0, issues.size(), 'Rows keep an event that was switched off: ' + textOf(issues));
        issues = CommissionConfigValidator.check(config, false);
        System.assert(codesOf(issues).contains('STAGE_TRIGGER_INVALID'), 'A new row cannot use it: ' + textOf(issues));

        // Only active rows count
        for (Commission_Stage__c row : stages) {
            if (String.isBlank(row.Designation__c) && row.Stage_Type__c == 'Final') {
                row.Active__c = false;
            }
        }
        Set<String> codes = codesOf(CommissionConfigValidator.checkRecords(saved, stages, rates, true));
        System.assertEquals(new Set<String>{ 'STAGE_FINAL_REQUIRED', 'STAGES_TOTAL' }, codes, 'A switched-off row is not there');
    }

    @IsTest
    static void namesAndFilledLabels() {
        CommissionTestData.useCatalog();
        System.assertEquals(CommissionConfigValidator.COMMISSION_STAGE_INITIAL, CommissionConfigValidator.stageName('Initial', null, null), 'Initial');
        System.assertEquals(CommissionConfigValidator.COMMISSION_STAGE_FINAL, CommissionConfigValidator.stageName('Final', null, ''), 'Final');
        System.assertEquals(CommissionConfigValidator.COMMISSION_STAGE_MID, CommissionConfigValidator.stageName('Mid', null, null), 'A Mid stage without a number');
        System.assertEquals(String.format(CommissionConfigValidator.COMMISSION_STAGE_MID_NUMBERED, new List<String>{ '2' }),
            CommissionConfigValidator.stageName('Mid', 2, null), 'Mid stages are numbered');
        System.assert(CommissionConfigValidator.stageName('Initial', null, 'CP_External').contains('CP External'), 'An own release names its designation');
        System.assertNotEquals(null, CommissionConfigValidator.stageName(null, null, null), 'A stage without a type still has a name');
        System.assertEquals('Unknown_Key', CommissionConfigValidator.designationLabel('Unknown_Key'), 'An unknown designation is shown by its key');

        String filled = CommissionConfigValidator.fill('{0} units until {1}{2}', new List<Object>{ 1000, Date.newInstance(2026, 9, 1), null });
        System.assert(filled.startsWith('1000 units until 01 '), 'Numbers stay plain and dates are written out: ' + filled);
        System.assert(filled.endsWith(' 2026'), 'The year closes the date: ' + filled);
        System.assertEquals('Plain', CommissionConfigValidator.fill('Plain', null), 'A label without values');
    }
}