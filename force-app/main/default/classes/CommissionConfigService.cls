// Loads, saves and moves a commission configuration through its life: draft, approval, new versions.
// Runs in system mode. Who may do what is decided through CommissionAccess; the triggers repeat the rules, so a
// save here runs as the user. Only the system steps (naming the approver, replacing or shortening the earlier
// version, carrying targets over) switch the trigger rules off.
public without sharing class CommissionConfigService {
    // Messages this class shows or sends
    @TestVisible private static final String COMMISSION_COMMON_ERROR = 'Something went wrong. Please try again.';
    @TestVisible private static final String COMMISSION_SERVICE_CHOICE_INVALID = 'This kind of change is not known. Reload the page and try again.';
    @TestVisible private static final String COMMISSION_SERVICE_CHOOSE_APPROVER = 'Choose who approves this configuration.';
    @TestVisible private static final String COMMISSION_SERVICE_CONSEQUENCE_CORRECTION = 'Replaces version {0} for its whole period.';
    @TestVisible private static final String COMMISSION_SERVICE_CONSEQUENCE_END_EARLY = 'The period ends on {0} instead of {1}.';
    @TestVisible private static final String COMMISSION_SERVICE_CONSEQUENCE_FROM_DATE = 'Applies to sales whose Initial payout event is on or after {0}. Earlier sales stay on version {1}.';
    @TestVisible private static final String COMMISSION_SERVICE_CONSEQUENCE_NEXT_PERIOD = 'A new period, starting the day after {0} ends.';
    @TestVisible private static final String COMMISSION_SERVICE_COPY_SAME_PROJECT = 'Choose another project. For this project use Next period or Change terms from a date.';
    @TestVisible private static final String COMMISSION_SERVICE_DECIDE_BLOCKED = 'You entered or edited this version, so another approver must decide it.';
    @TestVisible private static final String COMMISSION_SERVICE_DECIDE_FAILED = 'The decision could not be saved. {0}';
    @TestVisible private static final String COMMISSION_SERVICE_DECIDE_OTHER_APPROVER = 'This approval request is with {0}. Only {0} or an administrator can decide it.';
    @TestVisible private static final String COMMISSION_SERVICE_DECISION_INVALID = 'Choose Approve or Reject.';
    @TestVisible private static final String COMMISSION_SERVICE_DESIGNATION_UNKNOWN = '{0} can no longer be paid on a new configuration. Switch it off and save again.';
    @TestVisible private static final String COMMISSION_SERVICE_DISCARD_FAILED = 'The draft could not be discarded. {0}';
    @TestVisible private static final String COMMISSION_SERVICE_DISCARD_REFUSED = 'Only a draft can be discarded.';
    @TestVisible private static final String COMMISSION_SERVICE_MONTH_NAMES = 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec';
    @TestVisible private static final String COMMISSION_SERVICE_NO_APPROVER = 'Nobody is set up to approve commission configurations. Ask your Salesforce administrator.';
    @TestVisible private static final String COMMISSION_SERVICE_NO_REQUEST = 'No approval request is open for this configuration. Reload it.';
    @TestVisible private static final String COMMISSION_SERVICE_NOT_DRAFT = 'Only a draft can be changed. This configuration is now: {0}. Reload it.';
    @TestVisible private static final String COMMISSION_SERVICE_NOT_FOUND = 'This configuration no longer exists. Go back to the overview.';
    @TestVisible private static final String COMMISSION_SERVICE_NOT_PENDING = 'This configuration is not waiting for approval any more. Reload it.';
    @TestVisible private static final String COMMISSION_SERVICE_NOTHING_TO_SAVE = 'There is nothing to save.';
    @TestVisible private static final String COMMISSION_SERVICE_OPEN_DRAFT_EXISTS = 'There is already an open draft for this version: {0}. Open that draft, or discard it first.';
    @TestVisible private static final String COMMISSION_SERVICE_PERIOD_OVER = 'This period is already over. Use Next period, or Correct this version.';
    @TestVisible private static final String COMMISSION_SERVICE_PROJECT_MISSING = 'This project no longer exists.';
    @TestVisible private static final String COMMISSION_SERVICE_PROJECT_REQUIRED = 'Choose the project to copy this configuration to.';
    @TestVisible private static final String COMMISSION_SERVICE_REJECT_NEEDS_COMMENT = 'Enter a comment to reject. Finance sees it with the returned draft.';
    @TestVisible private static final String COMMISSION_SERVICE_SAVE_FAILED = 'The configuration could not be saved. {0}';
    @TestVisible private static final String COMMISSION_SERVICE_SOMEONE = 'Someone else';
    @TestVisible private static final String COMMISSION_SERVICE_SOURCE_MISSING = 'The approved version this draft is based on could not be found.';
    @TestVisible private static final String COMMISSION_SERVICE_SOURCE_NOT_APPROVED = 'A new draft can only be made from an approved configuration.';
    @TestVisible private static final String COMMISSION_SERVICE_SOURCE_REPLACED = 'This version has been replaced. Start from the version that replaced it.';
    @TestVisible private static final String COMMISSION_SERVICE_STALE = '{0} changed this configuration on {1}, after you opened it. Reload it before you save, so that their changes are not lost.';
    @TestVisible private static final String COMMISSION_SERVICE_SUBMIT_FAILED = 'The configuration could not be submitted for approval. {0}';
    @TestVisible private static final String COMMISSION_SERVICE_WITHDRAW_FAILED = 'The configuration could not be withdrawn. {0}';
    @TestVisible private static final String COMMISSION_SERVICE_WITHDRAW_REFUSED = 'Only the person who submitted this configuration, or an administrator, can withdraw it.';
    @TestVisible private static final String COMMISSION_SERVICE_WITHDRAW_REFUSED_NAMED = 'Only {0}, who submitted this configuration, or an administrator can withdraw it.';
    @TestVisible private static final String COMMISSION_STATE_ACTIVE = 'Active';
    @TestVisible private static final String COMMISSION_STATE_DRAFT = 'Draft';
    @TestVisible private static final String COMMISSION_STATE_EXPIRED = 'Expired';
    @TestVisible private static final String COMMISSION_STATE_PENDING = 'With CCO since {0}';
    @TestVisible private static final String COMMISSION_STATE_PENDING_SHORT = 'With CCO';
    @TestVisible private static final String COMMISSION_STATE_REPLACED = 'Replaced by version {0}';
    @TestVisible private static final String COMMISSION_STATE_REPLACED_SHORT = 'Replaced';
    @TestVisible private static final String COMMISSION_STATE_RETURNED = 'Returned by CCO';
    @TestVisible private static final String COMMISSION_STATE_UPCOMING = 'Upcoming';


    // ------------------------------------------------------------ structural values

    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_PENDING = 'Pending Approval';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_SUPERSEDED = 'Superseded';
    public static final String DECISION_REJECTED = 'Rejected';

    public static final String STATE_DRAFT = 'DRAFT';
    public static final String STATE_RETURNED = 'RETURNED';
    public static final String STATE_PENDING = 'PENDING';
    public static final String STATE_UPCOMING = 'UPCOMING';
    public static final String STATE_ACTIVE = 'ACTIVE';
    public static final String STATE_EXPIRED = 'EXPIRED';
    public static final String STATE_REPLACED = 'REPLACED';

    public static final String CHANGE_NEW = 'New';
    public static final String CHANGE_CORRECTION = 'Correction';
    public static final String CHANGE_FROM_DATE = 'Change From Date';
    public static final String CHANGE_NEXT_PERIOD = 'Next Period';
    public static final String CHANGE_END_EARLY = 'End Early';
    public static final String CHANGE_COPY = 'Copy';

    public static final String CHOICE_CORRECTION = 'CORRECTION';
    public static final String CHOICE_CHANGE_FROM_DATE = 'CHANGE_FROM_DATE';
    public static final String CHOICE_NEXT_PERIOD = 'NEXT_PERIOD';
    public static final String CHOICE_END_EARLY = 'END_EARLY';
    public static final String CHOICE_COPY = 'COPY';

    public static final String DECIDE_APPROVE = 'APPROVE';
    public static final String DECIDE_REJECT = 'REJECT';

    public static final String BASELINE_SUPERSEDES = 'SUPERSEDES';
    public static final String BASELINE_PREVIOUS = 'PREVIOUS_PERIOD';

    private static final String STAGE_INITIAL = 'Initial';
    private static final String STAGE_MID = 'Mid';
    private static final String STAGE_FINAL = 'Final';
    private static final String RATE_PERCENT = 'Percent';
    private static final String RATE_FLAT = 'Flat';
    private static final String SPLIT_OWN = 'Own';
    private static final String SPLIT_SINGLE = 'Single';
    private static final String RELEASE_ALL_AT_INITIAL = 'All At Initial';
    private static final String TARGET_RULE_NONE = 'None';
    private static final String PARAMETER_PERCENT = 'Percent';
    private static final String PARAMETER_TRANCHE = 'Tranche';
    private static final String PARAMETER_INSTALLMENT = 'Installment';

    private static final String NOTIFY_SUBMITTED = 'SUBMITTED';
    // What the platform puts in front of a message a trigger added with addError
    private static final String RULE_MARKER = 'FIELD_CUSTOM_VALIDATION_EXCEPTION';

    private static final Map<String, String> CHANGE_BY_CHOICE = new Map<String, String>{
        CHOICE_CORRECTION => CHANGE_CORRECTION,
        CHOICE_CHANGE_FROM_DATE => CHANGE_FROM_DATE,
        CHOICE_NEXT_PERIOD => CHANGE_NEXT_PERIOD,
        CHOICE_END_EARLY => CHANGE_END_EARLY,
        CHOICE_COPY => CHANGE_COPY
    };
    private static final Set<String> CHANGE_TYPES = new Set<String>{
        CHANGE_NEW, CHANGE_CORRECTION, CHANGE_FROM_DATE, CHANGE_NEXT_PERIOD, CHANGE_END_EARLY, CHANGE_COPY
    };
    // Change types that take the place of the version named in Supersedes
    private static final Set<String> REPLACING = new Set<String>{ CHANGE_CORRECTION, CHANGE_FROM_DATE, CHANGE_END_EARLY };
    private static final Set<String> OPEN_STATUSES = new Set<String>{ STATUS_DRAFT, STATUS_PENDING };

    // Field list of a configuration for a SOQL string: enough for summary(), stateOf(), stateLabel() and decideBlockedReason()
    public static final String SUMMARY_FIELDS =
        'Id, Name, Reference__c, Version__c, Project__c, Project__r.Name, Start_Date__c, End_Date__c, Status__c, Decision__c, '
        + 'Change_Type__c, Supersedes__c, Superseded_By__c, Superseded_By__r.Version__c, Submitted_On__c, Submitted_By__c, '
        + 'Submitted_By__r.Name, Approver__c, Approver__r.Name, Editor_Ids__c, CreatedById, CreatedDate, LastModifiedById, '
        + 'LastModifiedBy.Name, LastModifiedDate';

    private static final String HEADER_FIELDS = SUMMARY_FIELDS
        + ', Project__r.Company__c, Original_End_Date__c, Change_Reason__c, Carry_Over_Targets__c, Price_Excludes_Tax__c, '
        + 'Supersedes__r.Name, Supersedes__r.Version__c, Supersedes__r.End_Date__c, Superseded_By__r.Name, '
        + 'Approved_By__r.Name, Approved_On__c, Decision_Comments__c, Decision_By__r.Name, Decision_On__c';

    private static final String STAGE_FIELDS =
        'Id, Config__c, Stage_Type__c, Sequence__c, Trigger__c, Trigger_Label__c, Detector__c, Parameter_Type__c, '
        + 'Trigger_Percent__c, Trigger_Tranche__c, Trigger_Installment__c, Installment_Name__c, Release_Percent__c, '
        + 'Designation__c, Active__c, LastModifiedDate, LastModifiedBy.Name';

    private static final String RATE_FIELDS =
        'Id, Config__c, Designation__c, Designation_Label__c, Rate_Type__c, Current_Rate__c, Exceed_Rate__c, Flat_Amount__c, '
        + 'Target__c, Target_Basis__c, Target_Period__c, Exceed_Mode__c, Split__c, Release_Mode__c, Contract_Reference__c, '
        + 'Claim_Gate__c, Claim_Gate_Label__c, Claim_Mode__c, Aggregate_Of__c, Target_Rule__c, Active__c, '
        + 'LastModifiedDate, LastModifiedBy.Name';

    // The fields a save may write; a row is only updated when one of them really differs
    private static final List<Schema.SObjectField> STAGE_WRITES = new List<Schema.SObjectField>{
        Commission_Stage__c.Stage_Type__c, Commission_Stage__c.Sequence__c, Commission_Stage__c.Trigger__c,
        Commission_Stage__c.Trigger_Label__c, Commission_Stage__c.Detector__c, Commission_Stage__c.Parameter_Type__c,
        Commission_Stage__c.Trigger_Percent__c, Commission_Stage__c.Trigger_Tranche__c,
        Commission_Stage__c.Trigger_Installment__c, Commission_Stage__c.Release_Percent__c,
        Commission_Stage__c.Designation__c, Commission_Stage__c.Active__c
    };
    private static final List<Schema.SObjectField> RATE_WRITES = new List<Schema.SObjectField>{
        Commission_Rate__c.Designation__c, Commission_Rate__c.Designation_Label__c, Commission_Rate__c.Rate_Type__c,
        Commission_Rate__c.Current_Rate__c, Commission_Rate__c.Exceed_Rate__c, Commission_Rate__c.Flat_Amount__c,
        Commission_Rate__c.Target__c, Commission_Rate__c.Target_Basis__c, Commission_Rate__c.Target_Period__c,
        Commission_Rate__c.Exceed_Mode__c, Commission_Rate__c.Split__c, Commission_Rate__c.Release_Mode__c,
        Commission_Rate__c.Contract_Reference__c, Commission_Rate__c.Claim_Gate__c, Commission_Rate__c.Claim_Gate_Label__c,
        Commission_Rate__c.Claim_Mode__c, Commission_Rate__c.Aggregate_Of__c, Commission_Rate__c.Target_Rule__c,
        Commission_Rate__c.Active__c
    };
    private static final List<Schema.SObjectField> HEADER_WRITES = new List<Schema.SObjectField>{
        Commission_Config__c.Project__c, Commission_Config__c.Start_Date__c, Commission_Config__c.End_Date__c,
        Commission_Config__c.Change_Reason__c, Commission_Config__c.Carry_Over_Targets__c,
        Commission_Config__c.Price_Excludes_Tax__c
    };

    private static Integer keyCounter = 0;

    // The newest change of a configuration or one of its rows, and who made it
    private class Touch {
        Datetime at;
        String byName;
    }

    // ------------------------------------------------------------ reading

    // One configuration as the screens show it, with what the running user may do with it.
    public static CommissionDto.Config load(Id configId) {
        CommissionAccess.require(CommissionAccess.VIEW);
        Commission_Config__c record = fullRecord(configId);
        if (record == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOT_FOUND);
        }
        Date today = Date.today();
        CommissionDto.Config config = toDto(record, today);
        List<Commission_Config__c> others = projectConfigs(record.Project__c, record.Id);
        config.siblings = summaries(others);

        // An open draft that will replace or shorten this version
        Commission_Config__c openDraft = null;
        for (Commission_Config__c other : others) {
            if (other.Supersedes__c == record.Id && OPEN_STATUSES.contains(other.Status__c)) {
                openDraft = other;
                break;
            }
        }
        Boolean canConfigure = CommissionAccess.can(CommissionAccess.CONFIGURE);
        Boolean canApprove = CommissionAccess.can(CommissionAccess.APPROVE);
        Boolean isDraft = record.Status__c == STATUS_DRAFT;
        Boolean isPending = record.Status__c == STATUS_PENDING;
        config.canEdit = isDraft && canConfigure;
        config.canSubmit = config.canEdit;
        config.canDiscard = config.canEdit;
        config.canWithdraw = isPending && record.Submitted_By__c == UserInfo.getUserId();
        String blocked = isPending && canApprove ? decideBlockedReason(record) : null;
        if (isPending && canApprove && blocked == null) {
            blocked = otherApproverReason(record);
        }
        config.canDecide = isPending && canApprove && blocked == null;
        config.decideBlockedReason = blocked;
        config.canCreateFrom = record.Status__c == STATUS_APPROVED && config.state != STATE_REPLACED
            && canConfigure && openDraft == null;
        if (openDraft != null) {
            config.openDraftId = openDraft.Id;
            config.openDraftName = openDraft.Name;
        }

        // What it is compared with: the version it replaces, else the period it follows. That is the period that
        // ends the day before it starts, else the one that ended last before it starts.
        Commission_Config__c previous = null;
        if (record.Supersedes__c != null) {
            config.baseline = baselineOf(fullRecord(record.Supersedes__c), today);
            config.baselineKind = config.baseline == null ? null : BASELINE_SUPERSEDES;
        } else if (record.Change_Type__c == CHANGE_NEXT_PERIOD && record.Start_Date__c != null) {
            previous = periodEndingOn(others, record.Start_Date__c.addDays(-1));
            Commission_Config__c followed = previous != null ? previous : lastPeriodBefore(others, record.Start_Date__c);
            if (followed != null) {
                config.baseline = baselineOf(fullRecord(followed.Id), today);
                config.baselineKind = config.baseline == null ? null : BASELINE_PREVIOUS;
            }
        }
        config.consequence = consequenceText(
            record.Change_Type__c, record.Start_Date__c, record.End_Date__c,
            record.Supersedes__c == null ? null : record.Supersedes__r.Version__c,
            record.Supersedes__c == null ? null : record.Supersedes__r.End_Date__c,
            previous == null ? null : previous.Name
        );
        config.approvers = config.canEdit ? approvers() : new List<CommissionDto.Person>();
        return config;
    }

    // An unsaved draft for a new configuration: every designation is offered, none is paid yet.
    public static CommissionDto.Config blank(Id projectId) {
        CommissionAccess.require(CommissionAccess.CONFIGURE);
        CommissionDto.Config config = new CommissionDto.Config();
        if (projectId != null) {
            Project__c project = projectOf(projectId);
            config.projectId = project.Id;
            config.projectName = project.Name;
            config.companyId = project.Company__c;
        }
        config.version = 1;
        config.changeType = CHANGE_NEW;
        config.carryOverTargets = false;
        config.priceExcludesTax = false;
        config.stages = new List<CommissionDto.Stage>{ emptyStage(STAGE_INITIAL, 1) };
        if (CommissionCatalog.setting().Final_Stage_Required__c == true) {
            config.stages.add(emptyStage(STAGE_FINAL, 2));
        }
        config.rates = new List<CommissionDto.Rate>();
        for (CommissionDto.Designation entry : CommissionCatalog.designations()) {
            config.rates.add(unpaidRate(entry));
        }
        asUnsavedDraft(config, projectId);
        return config;
    }

    // An unsaved draft copied from an approved configuration. Nothing is stored until the first save.
    public static CommissionDto.Config draftFrom(Id sourceId, String choice, Id targetProjectId) {
        CommissionAccess.require(CommissionAccess.CONFIGURE);
        String changeType = choice == null ? null : CHANGE_BY_CHOICE.get(choice.trim().toUpperCase());
        if (changeType == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_CHOICE_INVALID);
        }
        Commission_Config__c source = fullRecord(sourceId);
        if (source == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOT_FOUND);
        }
        Date today = Date.today();
        if (source.Status__c != STATUS_APPROVED) {
            throw CommissionDto.error(COMMISSION_SERVICE_SOURCE_NOT_APPROVED);
        }
        if (changeType != CHANGE_COPY && stateOf(source, today) == STATE_REPLACED) {
            throw CommissionDto.error(COMMISSION_SERVICE_SOURCE_REPLACED);
        }

        CommissionDto.Config draft = toDto(source, today);
        draft.id = null;
        draft.name = null;
        draft.changeType = changeType;
        draft.changeReason = null;
        draft.carryOverTargets = false;
        draft.originalEndDate = null;
        draft.supersedesId = null;
        draft.supersedesName = null;
        draft.supersededById = null;
        draft.supersededByName = null;
        draft.approverId = null;
        draft.approverName = null;
        draft.submittedById = null;
        draft.submittedByName = null;
        draft.submittedOn = null;
        draft.approvedByName = null;
        draft.approvedOn = null;
        draft.decision = null;
        draft.decisionComments = null;
        draft.decisionByName = null;
        draft.decisionOn = null;
        draft.lastModified = null;
        for (CommissionDto.Stage stage : draft.stages) {
            stage.id = null;
            stage.key = newKey();
        }
        for (CommissionDto.Rate rate : draft.rates) {
            rate.id = null;
            rate.key = newKey();
        }

        String previousName = null;
        if (REPLACING.contains(changeType)) {
            refuseSecondDraft(source.Id, null);
            draft.supersedesId = source.Id;
            draft.supersedesName = source.Name;
            draft.reference = referenceOf(source);
            draft.version = nextVersion(draft.reference);
            if (changeType == CHANGE_FROM_DATE) {
                // From tomorrow at the earliest, and always after the first day of the version it changes
                Date startDate = today.addDays(1);
                if (startDate <= source.Start_Date__c) {
                    startDate = source.Start_Date__c.addDays(1);
                }
                if (startDate > source.End_Date__c) {
                    throw CommissionDto.error(COMMISSION_SERVICE_PERIOD_OVER);
                }
                draft.startDate = startDate;
            } else if (changeType == CHANGE_END_EARLY) {
                if (today > source.End_Date__c) {
                    throw CommissionDto.error(COMMISSION_SERVICE_PERIOD_OVER);
                }
                draft.endDate = today < source.Start_Date__c ? source.Start_Date__c : today;
            }
            draft.baseline = baselineOf(source, today);
            draft.baselineKind = BASELINE_SUPERSEDES;
        } else if (changeType == CHANGE_NEXT_PERIOD) {
            draft.reference = null;
            draft.version = 1;
            draft.startDate = source.End_Date__c.addDays(1);
            draft.endDate = sameLength(source.Start_Date__c, source.End_Date__c, draft.startDate);
            draft.carryOverTargets = true;
            draft.baseline = baselineOf(source, today);
            draft.baselineKind = BASELINE_PREVIOUS;
            previousName = source.Name;
        } else {
            if (targetProjectId == null) {
                throw CommissionDto.error(COMMISSION_SERVICE_PROJECT_REQUIRED);
            }
            if (targetProjectId == source.Project__c) {
                throw CommissionDto.error(COMMISSION_SERVICE_COPY_SAME_PROJECT);
            }
            Project__c target = projectOf(targetProjectId);
            draft.projectId = target.Id;
            draft.projectName = target.Name;
            draft.companyId = target.Company__c;
            draft.reference = null;
            draft.version = 1;
            draft.startDate = null;
            draft.endDate = null;
            blankForeignInstallments(draft.stages, target.Company__c);
        }
        draft.consequence = consequenceText(
            changeType, draft.startDate, draft.endDate, source.Version__c, source.End_Date__c, previousName
        );
        asUnsavedDraft(draft, draft.projectId);
        return draft;
    }

    // DRAFT, RETURNED, PENDING, UPCOMING, ACTIVE, EXPIRED or REPLACED.
    public static String stateOf(Commission_Config__c record, Date today) {
        if (record == null) {
            return null;
        }
        Date day = today == null ? Date.today() : today;
        String status = record.Status__c;
        if (status == STATUS_PENDING) {
            return STATE_PENDING;
        }
        if (status == STATUS_SUPERSEDED) {
            return STATE_REPLACED;
        }
        if (status == STATUS_APPROVED) {
            if (record.Start_Date__c != null && day < record.Start_Date__c) {
                return STATE_UPCOMING;
            }
            if (record.End_Date__c != null && day > record.End_Date__c) {
                // A shortened version is "replaced" once its shortened period is over
                return record.Superseded_By__c == null ? STATE_EXPIRED : STATE_REPLACED;
            }
            return STATE_ACTIVE;
        }
        return record.Decision__c == DECISION_REJECTED ? STATE_RETURNED : STATE_DRAFT;
    }

    // The state in words: "With CCO since 08 Oct", "Replaced by version 2", "Active" ...
    public static String stateLabel(Commission_Config__c record, Date today) {
        String state = stateOf(record, today);
        if (state == null) {
            return null;
        }
        if (state == STATE_RETURNED) {
            return COMMISSION_STATE_RETURNED;
        }
        if (state == STATE_PENDING) {
            return record.Submitted_On__c == null
                ? COMMISSION_STATE_PENDING_SHORT
                : String.format(COMMISSION_STATE_PENDING, new List<Object>{ formatDay(record.Submitted_On__c.date()) });
        }
        if (state == STATE_UPCOMING) {
            return COMMISSION_STATE_UPCOMING;
        }
        if (state == STATE_ACTIVE) {
            return COMMISSION_STATE_ACTIVE;
        }
        if (state == STATE_EXPIRED) {
            return COMMISSION_STATE_EXPIRED;
        }
        if (state == STATE_REPLACED) {
            Decimal newer = replacingVersion(record);
            return newer == null
                ? COMMISSION_STATE_REPLACED_SHORT
                : String.format(COMMISSION_STATE_REPLACED, new List<Object>{ wholeText(newer) });
        }
        return COMMISSION_STATE_DRAFT;
    }

    // The short form of a configuration for lists. The record must be queried with SUMMARY_FIELDS.
    public static CommissionDto.Summary summary(Commission_Config__c record) {
        if (record == null) {
            return null;
        }
        Date today = Date.today();
        CommissionDto.Summary summary = new CommissionDto.Summary();
        summary.id = record.Id;
        summary.name = record.Name;
        summary.reference = record.Reference__c;
        summary.version = whole(record.Version__c);
        summary.projectId = record.Project__c;
        summary.projectName = record.Project__r == null ? null : record.Project__r.Name;
        summary.startDate = record.Start_Date__c;
        summary.endDate = record.End_Date__c;
        summary.status = record.Status__c;
        summary.state = stateOf(record, today);
        summary.stateLabel = stateLabel(record, today);
        summary.changeType = record.Change_Type__c;
        summary.submittedOn = record.Submitted_On__c;
        summary.submittedByName = record.Submitted_By__r == null ? null : record.Submitted_By__r.Name;
        summary.approverName = record.Approver__r == null ? null : record.Approver__r.Name;
        summary.lastModifiedByName = record.LastModifiedBy == null ? null : record.LastModifiedBy.Name;
        summary.lastModified = record.LastModifiedDate;
        return summary;
    }

    // Why the running user, although an approver, may not decide this version: they entered, edited or submitted it.
    // Null when nothing stands in the way. Needs Editor_Ids__c, Submitted_By__c and CreatedById.
    public static String decideBlockedReason(Commission_Config__c record) {
        if (record == null || CommissionAccess.selfApprovalAllowed()) {
            return null;
        }
        Id me = UserInfo.getUserId();
        String shortId = String.valueOf(me).left(15);
        Boolean touched = record.Submitted_By__c == me || record.CreatedById == me
            || (record.Editor_Ids__c != null && record.Editor_Ids__c.contains(shortId));
        return touched ? COMMISSION_SERVICE_DECIDE_BLOCKED : null;
    }

    // Why an approver cannot decide a pending request that sits with somebody else: Salesforce lets only the
    // approver it is assigned to, or an administrator (Modify All Data), act on an approval request.
    public static String otherApproverReason(Commission_Config__c record) {
        if (record == null || record.Approver__c == null || record.Approver__c == UserInfo.getUserId() || canTakeOver()) {
            return null;
        }
        String holder = record.Approver__r == null || record.Approver__r.Name == null ? '' : record.Approver__r.Name;
        return String.format(COMMISSION_SERVICE_DECIDE_OTHER_APPROVER, new List<Object>{ holder });
    }

    private static final Map<Id, Boolean> TAKE_OVER = new Map<Id, Boolean>();

    private static Boolean canTakeOver() {
        Id me = UserInfo.getUserId();
        if (!TAKE_OVER.containsKey(me)) {
            TAKE_OVER.put(me, [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :me AND PermissionSet.PermissionsModifyAllData = true
                WITH SYSTEM_MODE
            ] > 0);
        }
        return TAKE_OVER.get(me);
    }

    // Who can approve a configuration the running user submits: the holders of an approving role; when nobody holds
    // one, the users of an approving profile. The submitter only when self-approval is allowed for them.
    public static List<CommissionDto.Person> approvers() {
        Set<String> roles = CommissionCatalog.listOf(CommissionCatalog.setting().Approve_Roles__c);
        List<User> users = roles == null || roles.isEmpty() ? null : CommissionAccess.usersInRoles(roles);
        if (users == null || users.isEmpty()) {
            users = CommissionAccess.usersWho(CommissionAccess.APPROVE);
        }
        Boolean selfAllowed = CommissionAccess.selfApprovalAllowed();
        Map<String, CommissionDto.Person> byName = new Map<String, CommissionDto.Person>();
        if (users != null) {
            for (User candidate : users) {
                if (candidate.Id == UserInfo.getUserId() && !selfAllowed) {
                    continue;
                }
                String name = candidate.Name == null ? '' : candidate.Name;
                byName.put(name.toLowerCase() + ' ' + candidate.Id, new CommissionDto.Person(candidate.Id, name));
            }
        }
        List<String> sortedKeys = new List<String>(byName.keySet());
        sortedKeys.sort();
        List<CommissionDto.Person> people = new List<CommissionDto.Person>();
        for (String key : sortedKeys) {
            people.add(byName.get(key));
        }
        return people;
    }

    // 01 Sep 2026
    public static String formatDate(Date value) {
        return value == null ? '' : formatDay(value) + ' ' + value.year();
    }

    // 08 Oct
    public static String formatDay(Date value) {
        if (value == null) {
            return '';
        }
        String day = String.valueOf(value.day()).leftPad(2, '0');
        List<String> months = COMMISSION_SERVICE_MONTH_NAMES.split(',');
        if (months.size() != 12) {
            // The label was edited into something else: fall back to the platform's month name
            return Datetime.newInstance(value.year(), value.month(), value.day()).format('dd MMM');
        }
        return day + ' ' + months[value.month() - 1].trim();
    }

    // ------------------------------------------------------------ saving

    // Saves the whole configuration in one transaction; with submit also sends it for approval.
    // With validation issues nothing is saved and the issues are returned.
    public static CommissionDto.SaveResult save(CommissionDto.Config config, Boolean submit) {
        CommissionAccess.require(CommissionAccess.CONFIGURE);
        if (config == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOTHING_TO_SAVE);
        }
        Boolean forSubmit = submit == true;
        Date today = Date.today();

        Commission_Config__c existing = null;
        if (config.id != null) {
            existing = fullRecord(config.id);
            if (existing == null) {
                throw CommissionDto.error(COMMISSION_SERVICE_NOT_FOUND);
            }
            if (existing.Status__c != STATUS_DRAFT) {
                throw CommissionDto.error(String.format(
                    COMMISSION_SERVICE_NOT_DRAFT, new List<Object>{ stateLabel(existing, today) }
                ));
            }
            refuseStale(config, existing);
        }
        Commission_Config__c source = existing == null ? sourceOfNew(config) : null;
        CommissionDto.Config working = normalised(config, existing, source);

        CommissionDto.SaveResult result = new CommissionDto.SaveResult();
        result.saved = false;
        result.submitted = false;
        result.issues = CommissionConfigValidator.check(working, forSubmit);
        if (result.issues == null) {
            result.issues = new List<CommissionDto.Issue>();
        }
        if (!result.issues.isEmpty()) {
            // The screen keeps its own copy and pins the issues to the fields
            result.config = config;
            return result;
        }

        Savepoint beforeSave = Database.setSavepoint();
        Id configId;
        try {
            configId = store(working, existing, source);
            if (forSubmit) {
                submitForApproval(configId, config.approverId);
            }
        } catch (Exception problem) {
            // Nothing half-saved: header, rows and submission go together
            Database.rollback(beforeSave);
            throw refusal(problem, forSubmit ? COMMISSION_SERVICE_SUBMIT_FAILED : COMMISSION_SERVICE_SAVE_FAILED);
        }
        if (forSubmit) {
            CommissionNotifier.enqueue(NOTIFY_SUBMITTED, new Set<Id>{ configId });
        }
        result.config = load(configId);
        result.saved = true;
        result.submitted = forSubmit;
        return result;
    }

    // Deletes a draft, also one that was returned or withdrawn
    public static void discard(Id configId) {
        CommissionAccess.require(CommissionAccess.CONFIGURE);
        Commission_Config__c record = headerOf(configId);
        if (record == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOT_FOUND);
        }
        if (record.Status__c != STATUS_DRAFT) {
            throw CommissionDto.error(COMMISSION_SERVICE_DISCARD_REFUSED);
        }
        try {
            delete as system record;
        } catch (Exception problem) {
            throw refusal(problem, COMMISSION_SERVICE_DISCARD_FAILED);
        }
    }

    // Takes a submitted configuration back to Draft. The platform lets only the submitter or an administrator do it.
    public static CommissionDto.Config withdraw(Id configId) {
        CommissionAccess.require(CommissionAccess.CONFIGURE);
        Commission_Config__c record = headerOf(configId);
        if (record == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOT_FOUND);
        }
        if (record.Status__c != STATUS_PENDING) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOT_PENDING);
        }
        Savepoint beforeWithdraw = Database.setSavepoint();
        try {
            ProcessInstanceWorkitem item = pendingItem(configId);
            if (item == null) {
                throw CommissionDto.error(COMMISSION_SERVICE_NO_REQUEST);
            }
            Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
            request.setWorkitemId(item.Id);
            request.setAction('Removed');
            requireSuccess(Approval.process(request));
        } catch (Exception problem) {
            Database.rollback(beforeWithdraw);
            if (problem instanceof AuraHandledException || isRuleMessage(problem)) {
                throw refusal(problem, COMMISSION_SERVICE_WITHDRAW_FAILED);
            }
            String submitter = record.Submitted_By__r == null ? null : record.Submitted_By__r.Name;
            throw CommissionDto.error(String.isBlank(submitter)
                ? COMMISSION_SERVICE_WITHDRAW_REFUSED
                : String.format(COMMISSION_SERVICE_WITHDRAW_REFUSED_NAMED, new List<Object>{ submitter }));
        }
        return load(configId);
    }

    // The approver's decision, through the approval process (so the standard approval pages follow the same rules).
    public static CommissionDto.Config decide(Id configId, String decision, String comments) {
        CommissionAccess.require(CommissionAccess.APPROVE);
        String choice = decision == null ? '' : decision.trim().toUpperCase();
        if (choice != DECIDE_APPROVE && choice != DECIDE_REJECT) {
            throw CommissionDto.error(COMMISSION_SERVICE_DECISION_INVALID);
        }
        Commission_Config__c record = headerOf(configId);
        if (record == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOT_FOUND);
        }
        if (record.Status__c != STATUS_PENDING) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOT_PENDING);
        }
        if (choice == DECIDE_REJECT && String.isBlank(comments)) {
            throw CommissionDto.error(COMMISSION_SERVICE_REJECT_NEEDS_COMMENT);
        }
        String blocked = decideBlockedReason(record);
        if (blocked == null) {
            blocked = otherApproverReason(record);
        }
        if (blocked != null) {
            throw CommissionDto.error(blocked);
        }
        Savepoint beforeDecision = Database.setSavepoint();
        try {
            ProcessInstanceWorkitem item = pendingItem(configId);
            if (item == null) {
                throw CommissionDto.error(COMMISSION_SERVICE_NO_REQUEST);
            }
            // The request sits with the approver Finance chose; an administrator takes it over before deciding
            if (item.ActorId != UserInfo.getUserId()) {
                item.ActorId = UserInfo.getUserId();
                update as system item;
            }
            Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
            request.setWorkitemId(item.Id);
            request.setAction(choice == DECIDE_APPROVE ? 'Approve' : 'Reject');
            request.setComments(String.isBlank(comments) ? null : comments.trim());
            requireSuccess(Approval.process(request));
        } catch (Exception problem) {
            Database.rollback(beforeDecision);
            throw refusal(problem, COMMISSION_SERVICE_DECIDE_FAILED);
        }
        return load(configId);
    }

    // Called by the trigger for configurations that have just been approved: the earlier version is replaced or
    // shortened, and personal targets move on to a next period. Approved periods of a project never overlap.
    public static void afterApproval(List<Commission_Config__c> approved) {
        if (approved == null || approved.isEmpty()) {
            return;
        }
        Set<Id> approvedIds = new Set<Id>();
        Set<Id> earlierIds = new Set<Id>();
        Set<Id> carryProjects = new Set<Id>();
        for (Commission_Config__c fresh : approved) {
            approvedIds.add(fresh.Id);
            if (fresh.Supersedes__c != null && REPLACING.contains(fresh.Change_Type__c)) {
                earlierIds.add(fresh.Supersedes__c);
            }
            if (fresh.Change_Type__c == CHANGE_NEXT_PERIOD && fresh.Carry_Over_Targets__c == true
                    && fresh.Start_Date__c != null && fresh.Project__c != null) {
                carryProjects.add(fresh.Project__c);
            }
        }

        List<Commission_Config__c> changes = new List<Commission_Config__c>();
        if (!earlierIds.isEmpty()) {
            Map<Id, Commission_Config__c> earlierById = new Map<Id, Commission_Config__c>([
                SELECT Id, Project__c, Status__c, Start_Date__c, End_Date__c, Original_End_Date__c, Superseded_By__c
                FROM Commission_Config__c
                WHERE Id IN :earlierIds
                WITH SYSTEM_MODE
            ]);
            for (Commission_Config__c fresh : approved) {
                Commission_Config__c earlier = fresh.Supersedes__c == null || !REPLACING.contains(fresh.Change_Type__c)
                    ? null : earlierById.get(fresh.Supersedes__c);
                // Only a version that is still in force can be replaced, and only by a version of its own project
                if (earlier == null || earlier.Status__c != STATUS_APPROVED || earlier.Project__c != fresh.Project__c) {
                    continue;
                }
                Commission_Config__c change = new Commission_Config__c(Id = earlier.Id, Superseded_By__c = fresh.Id);
                Boolean startsLater = fresh.Change_Type__c == CHANGE_FROM_DATE && fresh.Start_Date__c != null
                    && earlier.Start_Date__c != null && fresh.Start_Date__c > earlier.Start_Date__c;
                if (startsLater) {
                    // Earlier sales stay on the earlier version: it ends the day before the new one starts
                    if (earlier.Original_End_Date__c == null) {
                        change.Original_End_Date__c = earlier.End_Date__c;
                    }
                    change.End_Date__c = fresh.Start_Date__c.addDays(-1);
                } else {
                    change.Status__c = STATUS_SUPERSEDED;
                }
                changes.add(change);
            }
        }

        // The period a next period follows: the approved configuration of the project that ended last before it
        // starts. Normally that is the day before; earlier when that period was ended early or corrected meanwhile.
        Map<Id, List<Commission_Config__c>> endedByProject = new Map<Id, List<Commission_Config__c>>();
        if (!carryProjects.isEmpty()) {
            for (Commission_Config__c previous : [
                SELECT Id, Name, Reference__c, Project__c, End_Date__c
                FROM Commission_Config__c
                WHERE Project__c IN :carryProjects AND Status__c = :STATUS_APPROVED AND End_Date__c != null
                    AND Id NOT IN :approvedIds
                WITH SYSTEM_MODE
                ORDER BY End_Date__c DESC, Version__c DESC
            ]) {
                if (!endedByProject.containsKey(previous.Project__c)) {
                    endedByProject.put(previous.Project__c, new List<Commission_Config__c>());
                }
                endedByProject.get(previous.Project__c).add(previous);
            }
        }

        Boolean bypassBefore = CommissionTriggerHandler.bypass;
        CommissionTriggerHandler.bypass = true;
        try {
            if (!changes.isEmpty()) {
                update as system changes;
            }
            for (Commission_Config__c fresh : approved) {
                if (fresh.Change_Type__c != CHANGE_NEXT_PERIOD || fresh.Carry_Over_Targets__c != true
                        || fresh.Start_Date__c == null) {
                    continue;
                }
                Commission_Config__c previous = null;
                List<Commission_Config__c> ended = endedByProject.get(fresh.Project__c);
                if (ended != null) {
                    for (Commission_Config__c candidate : ended) {
                        // Latest end first: the first one that ended before the new period starts
                        if (candidate.End_Date__c < fresh.Start_Date__c) {
                            previous = candidate;
                            break;
                        }
                    }
                }
                String fromReference = previous == null ? null : referenceOf(previous);
                if (String.isNotBlank(fromReference)) {
                    CommissionTargetService.carryOver(fromReference, fresh);
                }
            }
        } finally {
            CommissionTriggerHandler.bypass = bypassBefore;
        }
    }

    // ------------------------------------------------------------ save: steps

    // Someone else saved after this copy was loaded: their work must not be overwritten.
    private static void refuseStale(CommissionDto.Config config, Commission_Config__c existing) {
        Touch latest = latestTouch(existing);
        if (config.lastModified == null || latest.at == null || latest.at <= config.lastModified) {
            return;
        }
        throw CommissionDto.error(String.format(COMMISSION_SERVICE_STALE, new List<Object>{
            String.isBlank(latest.byName) ? COMMISSION_SERVICE_SOMEONE : latest.byName,
            formatDate(latest.at.date()) + ', ' + latest.at.format('HH:mm')
        }));
    }

    // For a new draft that replaces or shortens a version: that version, checked. Null for the other kinds.
    private static Commission_Config__c sourceOfNew(CommissionDto.Config config) {
        String changeType = String.isBlank(config.changeType) ? CHANGE_NEW : config.changeType;
        if (!CHANGE_TYPES.contains(changeType)) {
            throw CommissionDto.error(COMMISSION_SERVICE_CHOICE_INVALID);
        }
        if (!REPLACING.contains(changeType)) {
            return null;
        }
        Commission_Config__c source = headerOf(config.supersedesId);
        if (source == null) {
            throw CommissionDto.error(COMMISSION_SERVICE_SOURCE_MISSING);
        }
        if (source.Status__c != STATUS_APPROVED) {
            throw CommissionDto.error(COMMISSION_SERVICE_SOURCE_NOT_APPROVED);
        }
        if (stateOf(source, Date.today()) == STATE_REPLACED) {
            throw CommissionDto.error(COMMISSION_SERVICE_SOURCE_REPLACED);
        }
        refuseSecondDraft(source.Id, null);
        return source;
    }

    // Only one open draft may replace or shorten the same version.
    private static void refuseSecondDraft(Id sourceId, Id exceptId) {
        for (Commission_Config__c openDraft : [
            SELECT Id, Name
            FROM Commission_Config__c
            WHERE Supersedes__c = :sourceId AND Status__c IN :OPEN_STATUSES AND Id != :exceptId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ]) {
            throw CommissionDto.error(String.format(COMMISSION_SERVICE_OPEN_DRAFT_EXISTS, new List<Object>{ openDraft.Name }));
        }
    }

    // The configuration as it will be stored: only values the server trusts in the header, catalog values copied onto
    // the rows, unpaid designations left out, and the payout rows of own and single releases put in place. The copy
    // the screen sent is left untouched.
    private static CommissionDto.Config normalised(CommissionDto.Config config, Commission_Config__c existing, Commission_Config__c source) {
        Map<String, CommissionDto.Designation> designations = CommissionCatalog.designationByKey();
        Map<String, CommissionDto.TriggerOption> events = CommissionCatalog.triggerByKey();

        CommissionDto.Config working = new CommissionDto.Config();
        working.status = STATUS_DRAFT;
        working.state = STATE_DRAFT;
        working.startDate = config.startDate;
        working.endDate = config.endDate;
        working.changeReason = clean(config.changeReason);
        working.priceExcludesTax = config.priceExcludesTax == true;
        working.approverId = config.approverId;
        working.lastModified = config.lastModified;
        if (existing != null) {
            working.id = existing.Id;
            working.name = existing.Name;
            working.changeType = existing.Change_Type__c;
            working.supersedesId = existing.Supersedes__c;
            working.reference = existing.Reference__c;
            working.version = whole(existing.Version__c);
            // The project of a first draft can still be corrected; a new version stays with its project
            working.projectId = existing.Change_Type__c == CHANGE_NEW && config.projectId != null
                ? config.projectId : existing.Project__c;
            working.decision = existing.Decision__c;
        } else if (source != null) {
            working.changeType = config.changeType;
            working.supersedesId = source.Id;
            working.reference = referenceOf(source);
            working.version = nextVersion(working.reference);
            working.projectId = source.Project__c;
        } else {
            working.changeType = String.isBlank(config.changeType) ? CHANGE_NEW : config.changeType;
            working.version = 1;
            working.projectId = config.projectId;
        }
        working.carryOverTargets = working.changeType == CHANGE_NEXT_PERIOD && config.carryOverTargets == true;

        // Rows already stored, to keep the copied catalog values of a designation or event that was switched off since
        Map<Id, Commission_Stage__c> storedStages = new Map<Id, Commission_Stage__c>();
        Map<Id, Commission_Rate__c> storedRates = new Map<Id, Commission_Rate__c>();
        Map<String, Commission_Rate__c> storedRateByKey = new Map<String, Commission_Rate__c>();
        if (existing != null) {
            storedStages.putAll(existing.Stages__r);
            for (Commission_Rate__c stored : existing.Rates__r) {
                storedRates.put(stored.Id, stored);
                if (stored.Designation__c != null && (stored.Active__c == true || !storedRateByKey.containsKey(stored.Designation__c))) {
                    storedRateByKey.put(stored.Designation__c, stored);
                }
            }
        }

        // Rates: one per paid designation
        Map<String, CommissionDto.Rate> paidByKey = new Map<String, CommissionDto.Rate>();
        working.rates = new List<CommissionDto.Rate>();
        if (config.rates != null) {
            for (CommissionDto.Rate sent : config.rates) {
                if (sent == null || sent.paid == false || String.isBlank(sent.designation) || paidByKey.containsKey(sent.designation.trim())) {
                    continue;
                }
                CommissionDto.Rate rate = new CommissionDto.Rate();
                rate.designation = sent.designation.trim();
                rate.id = sent.id != null && storedRates.containsKey(sent.id) ? sent.id : null;
                rate.key = String.isBlank(sent.key) ? newKey() : sent.key;
                rate.paid = true;
                CommissionDto.Designation entry = designations.get(rate.designation);
                Commission_Rate__c stored = rate.id != null ? storedRates.get(rate.id) : storedRateByKey.get(rate.designation);
                if (entry != null) {
                    rate.label = entry.label;
                    rate.rateType = entry.rateType;
                    rate.split = entry.split;
                    rate.targetRule = entry.targetRule;
                    rate.claimLabel = entry.claimLabel;
                    rate.aggregateOf = entry.aggregateOf;
                } else if (stored != null && stored.Designation__c == rate.designation) {
                    rate.label = stored.Designation_Label__c;
                    rate.rateType = stored.Rate_Type__c;
                    rate.split = stored.Split__c;
                    rate.targetRule = stored.Target_Rule__c;
                    rate.claimLabel = stored.Claim_Gate_Label__c;
                    rate.aggregateOf = stored.Aggregate_Of__c;
                } else {
                    throw CommissionDto.error(String.format(
                        COMMISSION_SERVICE_DESIGNATION_UNKNOWN,
                        new List<Object>{ String.isBlank(sent.label) ? rate.designation : sent.label }
                    ));
                }
                if (rate.rateType == RATE_FLAT) {
                    rate.flatAmount = scaled(sent.flatAmount, 2);
                } else {
                    rate.currentRate = scaled(sent.currentRate, 3);
                    rate.exceedRate = scaled(sent.exceedRate, 3);
                    rate.target = rate.targetRule == TARGET_RULE_NONE ? null : scaled(sent.target, 2);
                    rate.targetBasis = clean(sent.targetBasis);
                    rate.targetPeriod = clean(sent.targetPeriod);
                    rate.exceedMode = clean(sent.exceedMode);
                }
                rate.releaseMode = rate.split == SPLIT_OWN ? clean(sent.releaseMode) : null;
                rate.contractReference = clean(sent.contractReference);
                paidByKey.put(rate.designation, rate);
                working.rates.add(rate);
            }
        }

        // Stages the screen sent: the shared ones, and those of paid designations with their own release
        List<CommissionDto.Stage> shared = new List<CommissionDto.Stage>();
        Map<String, List<CommissionDto.Stage>> ownByKey = new Map<String, List<CommissionDto.Stage>>();
        if (config.stages != null) {
            for (CommissionDto.Stage sent : config.stages) {
                if (sent == null) {
                    continue;
                }
                String designation = clean(sent.designation);
                if (designation != null) {
                    CommissionDto.Rate owner = paidByKey.get(designation);
                    if (owner == null || owner.split != SPLIT_OWN) {
                        continue;
                    }
                }
                CommissionDto.Stage stage = new CommissionDto.Stage();
                stage.id = sent.id != null && storedStages.containsKey(sent.id) ? sent.id : null;
                stage.key = String.isBlank(sent.key) ? newKey() : sent.key;
                stage.stageType = clean(sent.stageType);
                stage.sequence = sent.sequence;
                stage.triggerKey = clean(sent.triggerKey);
                stage.triggerLabel = sent.triggerLabel;
                stage.parameterType = sent.parameterType;
                stage.triggerPercent = scaled(sent.triggerPercent, 2);
                stage.triggerTranche = sent.triggerTranche;
                stage.installmentId = sent.installmentId;
                stage.installmentName = sent.installmentName;
                stage.releasePercent = scaled(sent.releasePercent, 2);
                stage.designation = designation;
                if (designation == null) {
                    shared.add(stage);
                } else {
                    if (!ownByKey.containsKey(designation)) {
                        ownByKey.put(designation, new List<CommissionDto.Stage>());
                    }
                    ownByKey.get(designation).add(stage);
                }
            }
        }

        working.stages = new List<CommissionDto.Stage>();
        working.stages.addAll(inOrder(shared));
        for (CommissionDto.Rate rate : working.rates) {
            if (rate.split == SPLIT_OWN) {
                List<CommissionDto.Stage> own = ownByKey.containsKey(rate.designation)
                    ? ownByKey.get(rate.designation) : new List<CommissionDto.Stage>();
                if (rate.releaseMode == RELEASE_ALL_AT_INITIAL) {
                    // Everything at the Initial event: one row at 100 with the event the screen chose
                    CommissionDto.Stage only = null;
                    for (CommissionDto.Stage stage : own) {
                        if (stage.stageType == STAGE_INITIAL) {
                            only = stage;
                            break;
                        }
                    }
                    if (only == null) {
                        only = emptyStage(STAGE_INITIAL, 1);
                        only.designation = rate.designation;
                    }
                    only.releasePercent = 100;
                    own = new List<CommissionDto.Stage>{ only };
                }
                working.stages.addAll(inOrder(own));
            } else if (rate.split == SPLIT_SINGLE) {
                // One fixed payout event, never shown on the screen
                CommissionDto.Designation entry = designations.get(rate.designation);
                CommissionDto.Stage fixed = emptyStage(STAGE_INITIAL, 1);
                fixed.designation = rate.designation;
                fixed.releasePercent = 100;
                fixed.triggerKey = entry == null ? null : clean(entry.fixedTrigger);
                if (fixed.triggerKey == null && existing != null) {
                    for (Commission_Stage__c stored : existing.Stages__r) {
                        if (stored.Designation__c == rate.designation && stored.Stage_Type__c == STAGE_INITIAL) {
                            fixed.triggerKey = stored.Trigger__c;
                            fixed.id = stored.Id;
                            break;
                        }
                    }
                }
                working.stages.add(fixed);
            }
        }

        // The payout event's values are copied from the catalog; a parameter the event does not use is dropped
        for (CommissionDto.Stage stage : working.stages) {
            CommissionDto.TriggerOption option = stage.triggerKey == null ? null : events.get(stage.triggerKey);
            Commission_Stage__c stored = stage.id == null ? null : storedStages.get(stage.id);
            if (option != null) {
                stage.triggerLabel = option.label;
                stage.parameterType = option.parameterType;
            } else if (stored != null && stored.Trigger__c == stage.triggerKey) {
                stage.triggerLabel = stored.Trigger_Label__c;
                stage.parameterType = stored.Parameter_Type__c;
            } else {
                stage.triggerLabel = null;
                stage.parameterType = null;
            }
            if (stage.parameterType != PARAMETER_PERCENT) {
                stage.triggerPercent = null;
            }
            if (stage.parameterType != PARAMETER_TRANCHE) {
                stage.triggerTranche = null;
            }
            if (stage.parameterType != PARAMETER_INSTALLMENT) {
                stage.installmentId = null;
                stage.installmentName = null;
            }
        }
        return working;
    }

    // Initial first, the Mid rows by the sequence the screen gave them (rows without one keep their place in the
    // list, after the others), Final last; numbered again from 1.
    private static List<CommissionDto.Stage> inOrder(List<CommissionDto.Stage> stages) {
        List<CommissionDto.Stage> ordered = new List<CommissionDto.Stage>();
        for (String stageType : new List<String>{ STAGE_INITIAL, STAGE_MID, STAGE_FINAL, null }) {
            List<CommissionDto.Stage> ofType = new List<CommissionDto.Stage>();
            for (CommissionDto.Stage stage : stages) {
                Boolean known = stage.stageType == STAGE_INITIAL || stage.stageType == STAGE_MID || stage.stageType == STAGE_FINAL;
                if (stageType == null ? !known : stage.stageType == stageType) {
                    // Put in after the last row that does not come later (keeps equal rows in the order they came)
                    Integer place = ofType.size();
                    while (place > 0 && comesLater(ofType[place - 1], stage)) {
                        place--;
                    }
                    if (place == ofType.size()) {
                        ofType.add(stage);
                    } else {
                        ofType.add(place, stage);
                    }
                }
            }
            ordered.addAll(ofType);
        }
        Integer position = 1;
        for (CommissionDto.Stage stage : ordered) {
            stage.sequence = position;
            position++;
        }
        return ordered;
    }

    // Whether the first row belongs after the second by its sequence
    private static Boolean comesLater(CommissionDto.Stage first, CommissionDto.Stage second) {
        if (second.sequence == null) {
            return false;
        }
        return first.sequence == null || first.sequence > second.sequence;
    }

    // Writes header and rows. Runs as the user: the triggers check the lock.
    private static Id store(CommissionDto.Config working, Commission_Config__c existing, Commission_Config__c source) {
        Id configId;
        Boolean everSubmitted = existing != null && existing.Submitted_On__c != null;
        Commission_Config__c header = new Commission_Config__c(
            Project__c = working.projectId,
            Start_Date__c = working.startDate,
            End_Date__c = working.endDate,
            Change_Reason__c = working.changeReason,
            Carry_Over_Targets__c = working.carryOverTargets == true,
            Price_Excludes_Tax__c = working.priceExcludesTax == true
        );
        if (existing == null) {
            header.Status__c = STATUS_DRAFT;
            header.Change_Type__c = working.changeType;
            header.Version__c = working.version;
            configId = source == null ? insertHeader(header) : insertVersion(header, working, source);
        } else {
            configId = existing.Id;
            Commission_Config__c change = (Commission_Config__c) changesOf(header, existing, HEADER_WRITES);
            if (change != null) {
                update as system change;
            }
        }

        Map<String, CommissionDto.Designation> designations = CommissionCatalog.designationByKey();
        Map<String, CommissionDto.TriggerOption> events = CommissionCatalog.triggerByKey();

        // ---- payout stages
        List<Commission_Stage__c> storedStages = existing == null ? new List<Commission_Stage__c>() : existing.Stages__r;
        Map<Id, Commission_Stage__c> stageById = new Map<Id, Commission_Stage__c>(storedStages);
        Set<Id> keptStages = new Set<Id>();
        for (CommissionDto.Stage stage : working.stages) {
            if (stage.id != null) {
                keptStages.add(stage.id);
            }
        }
        List<Commission_Stage__c> stageInserts = new List<Commission_Stage__c>();
        List<Commission_Stage__c> stageUpdates = new List<Commission_Stage__c>();
        List<Commission_Stage__c> stageDeletes = new List<Commission_Stage__c>();
        for (CommissionDto.Stage stage : working.stages) {
            Commission_Stage__c stored = stage.id == null ? null : stageById.get(stage.id);
            if (stored == null && stage.stageType != STAGE_MID) {
                // A row that came without an id takes over the stored row of the same split and stage type, if any
                for (Commission_Stage__c candidate : storedStages) {
                    if (!keptStages.contains(candidate.Id) && candidate.Stage_Type__c == stage.stageType
                            && candidate.Designation__c == stage.designation) {
                        stored = candidate;
                        keptStages.add(candidate.Id);
                        break;
                    }
                }
            }
            Commission_Stage__c row = new Commission_Stage__c(
                Stage_Type__c = stage.stageType,
                Sequence__c = stage.sequence,
                Trigger__c = stage.triggerKey,
                Trigger_Label__c = stage.triggerLabel,
                Parameter_Type__c = stage.parameterType,
                Trigger_Percent__c = stage.triggerPercent,
                Trigger_Tranche__c = stage.triggerTranche,
                Trigger_Installment__c = stage.installmentId,
                Release_Percent__c = stage.releasePercent,
                Designation__c = stage.designation,
                Active__c = true
            );
            CommissionDto.TriggerOption option = stage.triggerKey == null ? null : events.get(stage.triggerKey);
            if (option != null) {
                row.Detector__c = option.detector;
            } else if (stored != null && stored.Trigger__c == stage.triggerKey) {
                row.Detector__c = stored.Detector__c;
            }
            if (stored == null) {
                row.Config__c = configId;
                stageInserts.add(row);
            } else {
                Commission_Stage__c change = (Commission_Stage__c) changesOf(row, stored, STAGE_WRITES);
                if (change != null) {
                    stageUpdates.add(change);
                }
            }
        }
        for (Commission_Stage__c stored : storedStages) {
            if (keptStages.contains(stored.Id) || stored.Active__c != true) {
                continue;
            }
            // Once submitted, a removed row is kept (switched off) so that its history survives
            if (everSubmitted) {
                stageUpdates.add(new Commission_Stage__c(Id = stored.Id, Active__c = false));
            } else {
                stageDeletes.add(stored);
            }
        }

        // ---- rates
        List<Commission_Rate__c> storedRates = existing == null ? new List<Commission_Rate__c>() : existing.Rates__r;
        Map<Id, Commission_Rate__c> rateById = new Map<Id, Commission_Rate__c>(storedRates);
        Set<Id> keptRates = new Set<Id>();
        for (CommissionDto.Rate rate : working.rates) {
            if (rate.id != null) {
                keptRates.add(rate.id);
            }
        }
        List<Commission_Rate__c> rateInserts = new List<Commission_Rate__c>();
        List<Commission_Rate__c> rateUpdates = new List<Commission_Rate__c>();
        List<Commission_Rate__c> rateDeletes = new List<Commission_Rate__c>();
        for (CommissionDto.Rate rate : working.rates) {
            Commission_Rate__c stored = rate.id == null ? null : rateById.get(rate.id);
            if (stored == null) {
                // A designation that is paid again takes its stored row back
                for (Commission_Rate__c candidate : storedRates) {
                    if (!keptRates.contains(candidate.Id) && candidate.Designation__c == rate.designation) {
                        stored = candidate;
                        keptRates.add(candidate.Id);
                        break;
                    }
                }
            }
            Commission_Rate__c row = new Commission_Rate__c(
                Designation__c = rate.designation,
                Designation_Label__c = rate.label,
                Rate_Type__c = rate.rateType,
                Current_Rate__c = rate.currentRate,
                Exceed_Rate__c = rate.exceedRate,
                Flat_Amount__c = rate.flatAmount,
                Target__c = rate.target,
                Target_Basis__c = rate.targetBasis,
                Target_Period__c = rate.targetPeriod,
                Exceed_Mode__c = rate.exceedMode,
                Split__c = rate.split,
                Release_Mode__c = rate.releaseMode,
                Contract_Reference__c = rate.contractReference,
                Claim_Gate_Label__c = rate.claimLabel,
                Aggregate_Of__c = rate.aggregateOf,
                Target_Rule__c = rate.targetRule,
                Active__c = true
            );
            CommissionDto.Designation entry = designations.get(rate.designation);
            if (entry != null) {
                row.Claim_Gate__c = entry.claimGate;
                row.Claim_Mode__c = entry.claimMode;
            } else if (stored != null) {
                row.Claim_Gate__c = stored.Claim_Gate__c;
                row.Claim_Mode__c = stored.Claim_Mode__c;
            }
            if (stored == null) {
                row.Config__c = configId;
                rateInserts.add(row);
            } else {
                Commission_Rate__c change = (Commission_Rate__c) changesOf(row, stored, RATE_WRITES);
                if (change != null) {
                    rateUpdates.add(change);
                }
            }
        }
        for (Commission_Rate__c stored : storedRates) {
            if (keptRates.contains(stored.Id) || stored.Active__c != true) {
                continue;
            }
            if (everSubmitted) {
                rateUpdates.add(new Commission_Rate__c(Id = stored.Id, Active__c = false));
            } else {
                rateDeletes.add(stored);
            }
        }

        // Removed rows go first, so that a replaced Initial or Final never stands beside its successor
        if (!stageDeletes.isEmpty()) {
            delete as system stageDeletes;
        }
        if (!rateDeletes.isEmpty()) {
            delete as system rateDeletes;
        }
        // A deleted row leaves nothing a stale copy could be compared with: the header carries the moment instead
        if (existing != null && (!stageDeletes.isEmpty() || !rateDeletes.isEmpty())) {
            update as system new Commission_Config__c(Id = configId);
        }
        if (!stageUpdates.isEmpty()) {
            update as system stageUpdates;
        }
        if (!rateUpdates.isEmpty()) {
            update as system rateUpdates;
        }
        if (!stageInserts.isEmpty()) {
            insert as system stageInserts;
        }
        if (!rateInserts.isEmpty()) {
            insert as system rateInserts;
        }
        return configId;
    }

    // The first version of a configuration: the trigger gives it its reference and version key.
    private static Id insertHeader(Commission_Config__c header) {
        insert as system header;
        return header.Id;
    }

    // A further version of an existing configuration keeps the reference and takes the next version number.
    // Written as the user, like a first version: the trigger keeps the reference, version and source it is given,
    // writes the version key and notes who entered it.
    private static Id insertVersion(Commission_Config__c header, CommissionDto.Config working, Commission_Config__c source) {
        header.Supersedes__c = source.Id;
        header.Reference__c = working.reference;
        insert as system header;
        return header.Id;
    }

    // Names the approver (a system step: the field is not Finance's to edit) and starts the approval process.
    private static void submitForApproval(Id configId, Id chosenApproverId) {
        List<CommissionDto.Person> candidates = approvers();
        Id approverId = null;
        for (CommissionDto.Person candidate : candidates) {
            if (chosenApproverId != null && candidate.id == chosenApproverId) {
                approverId = candidate.id;
            }
        }
        if (approverId == null) {
            if (candidates.isEmpty()) {
                throw CommissionDto.error(COMMISSION_SERVICE_NO_APPROVER);
            }
            if (candidates.size() > 1) {
                throw CommissionDto.error(COMMISSION_SERVICE_CHOOSE_APPROVER);
            }
            approverId = candidates[0].id;
        }
        Boolean bypassBefore = CommissionTriggerHandler.bypass;
        CommissionTriggerHandler.bypass = true;
        try {
            Commission_Config__c named = new Commission_Config__c(Id = configId, Approver__c = approverId);
            update as system named;
        } finally {
            CommissionTriggerHandler.bypass = bypassBefore;
        }
        Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
        request.setObjectId(configId);
        request.setSubmitterId(UserInfo.getUserId());
        String processName = CommissionCatalog.setting().Approval_Process__c;
        if (String.isNotBlank(processName)) {
            request.setProcessDefinitionNameOrId(processName.trim());
        }
        requireSuccess(Approval.process(request));
    }

    private static void requireSuccess(Approval.ProcessResult outcome) {
        if (outcome == null || outcome.isSuccess()) {
            return;
        }
        List<Database.Error> errors = outcome.getErrors();
        throw CommissionDto.error(errors == null || errors.isEmpty() ? COMMISSION_COMMON_ERROR : tidyMessage(errors[0].getMessage()));
    }

    private static ProcessInstanceWorkitem pendingItem(Id configId) {
        List<ProcessInstanceWorkitem> items = [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :configId AND ProcessInstance.Status = 'Pending'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return items.isEmpty() ? null : items[0];
    }

    // ------------------------------------------------------------ errors

    // What the screen is told when a save, a submission or a decision failed. A message a trigger gave is shown as
    // it is; anything else goes behind a sentence that says what could not be done.
    private static AuraHandledException refusal(Exception problem, String sentence) {
        if (problem instanceof AuraHandledException) {
            return (AuraHandledException) problem;
        }
        String message = messageOf(problem);
        if (isRuleMessage(problem) && String.isNotBlank(message)) {
            return CommissionDto.error(message);
        }
        return CommissionDto.error(String.format(sentence, new List<Object>{ message }).trim());
    }

    private static Boolean isRuleMessage(Exception problem) {
        if (problem instanceof DmlException) {
            DmlException failed = (DmlException) problem;
            if (failed.getNumDml() > 0 && failed.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
                return true;
            }
        }
        String message = problem.getMessage();
        return message != null && message.contains(RULE_MARKER);
    }

    // The message of an exception without the platform's wrapping
    public static String messageOf(Exception problem) {
        if (problem == null) {
            return '';
        }
        String message = problem.getMessage();
        if (problem instanceof DmlException && ((DmlException) problem).getNumDml() > 0) {
            message = ((DmlException) problem).getDmlMessage(0);
        }
        return tidyMessage(message);
    }

    // "Update failed. First exception on row 0 with id ...; first error: FIELD_CUSTOM_VALIDATION_EXCEPTION, The text: []" -> "The text"
    @TestVisible
    private static String tidyMessage(String message) {
        if (message == null) {
            return '';
        }
        String text = message;
        Integer at = text.lastIndexOf(RULE_MARKER);
        if (at >= 0) {
            text = text.substring(at + RULE_MARKER.length()).removeStart(',');
        }
        text = text.replaceFirst('(?s):\\s*\\[[^\\]]*\\]\\s*$', '');
        return text.trim();
    }

    // ------------------------------------------------------------ mapping

    private static Commission_Config__c fullRecord(Id configId) {
        if (configId == null || configId.getSObjectType() != Commission_Config__c.SObjectType) {
            return null;
        }
        String soql = 'SELECT ' + HEADER_FIELDS
            + ', (SELECT ' + STAGE_FIELDS + ' FROM Stages__r ORDER BY Designation__c NULLS FIRST, Sequence__c NULLS LAST, Name)'
            + ', (SELECT ' + RATE_FIELDS + ' FROM Rates__r ORDER BY Name)'
            + ' FROM Commission_Config__c WHERE Id = :configId';
        List<Commission_Config__c> found = (List<Commission_Config__c>) Database.queryWithBinds(
            soql, new Map<String, Object>{ 'configId' => configId }, AccessLevel.SYSTEM_MODE
        );
        return found.isEmpty() ? null : found[0];
    }

    private static Commission_Config__c headerOf(Id configId) {
        if (configId == null || configId.getSObjectType() != Commission_Config__c.SObjectType) {
            return null;
        }
        List<Commission_Config__c> found = (List<Commission_Config__c>) Database.queryWithBinds(
            'SELECT ' + SUMMARY_FIELDS + ' FROM Commission_Config__c WHERE Id = :configId',
            new Map<String, Object>{ 'configId' => configId }, AccessLevel.SYSTEM_MODE
        );
        return found.isEmpty() ? null : found[0];
    }

    // The configurations of a project that still count (not replaced completely), without one of them
    private static List<Commission_Config__c> projectConfigs(Id projectId, Id exceptId) {
        if (projectId == null) {
            return new List<Commission_Config__c>();
        }
        return (List<Commission_Config__c>) Database.queryWithBinds(
            'SELECT ' + SUMMARY_FIELDS + ' FROM Commission_Config__c'
                + ' WHERE Project__c = :projectId AND Status__c != :superseded AND Id != :exceptId'
                + ' ORDER BY Start_Date__c, Version__c, CreatedDate',
            new Map<String, Object>{ 'projectId' => projectId, 'superseded' => STATUS_SUPERSEDED, 'exceptId' => exceptId },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Project__c projectOf(Id projectId) {
        List<Project__c> found = [SELECT Id, Name, Company__c FROM Project__c WHERE Id = :projectId WITH SYSTEM_MODE];
        if (found.isEmpty()) {
            throw CommissionDto.error(COMMISSION_SERVICE_PROJECT_MISSING);
        }
        return found[0];
    }

    private static List<CommissionDto.Summary> summaries(List<Commission_Config__c> records) {
        List<CommissionDto.Summary> result = new List<CommissionDto.Summary>();
        for (Commission_Config__c record : records) {
            result.add(summary(record));
        }
        return result;
    }

    private static Commission_Config__c periodEndingOn(List<Commission_Config__c> records, Date lastDay) {
        for (Commission_Config__c record : records) {
            if (record.Status__c == STATUS_APPROVED && record.End_Date__c == lastDay) {
                return record;
            }
        }
        return null;
    }

    // The approved period that ended last before the given day
    private static Commission_Config__c lastPeriodBefore(List<Commission_Config__c> records, Date firstDay) {
        Commission_Config__c latest = null;
        for (Commission_Config__c record : records) {
            if (record.Status__c == STATUS_APPROVED && record.End_Date__c != null && record.End_Date__c < firstDay
                    && (latest == null || record.End_Date__c >= latest.End_Date__c)) {
                latest = record;
            }
        }
        return latest;
    }

    // The version a configuration is compared with; it does not carry a baseline of its own
    private static CommissionDto.Config baselineOf(Commission_Config__c record, Date today) {
        if (record == null) {
            return null;
        }
        CommissionDto.Config baseline = toDto(record, today);
        noActions(baseline);
        baseline.siblings = new List<CommissionDto.Summary>();
        baseline.approvers = new List<CommissionDto.Person>();
        return baseline;
    }

    private static void noActions(CommissionDto.Config config) {
        config.canEdit = false;
        config.canSubmit = false;
        config.canDiscard = false;
        config.canWithdraw = false;
        config.canDecide = false;
        config.canCreateFrom = false;
    }

    // The common part of blank() and draftFrom(): a draft that exists only on the screen
    private static void asUnsavedDraft(CommissionDto.Config config, Id projectId) {
        config.status = STATUS_DRAFT;
        config.state = STATE_DRAFT;
        config.stateLabel = COMMISSION_STATE_DRAFT;
        noActions(config);
        config.canEdit = true;
        config.canSubmit = true;
        config.decideBlockedReason = null;
        config.openDraftId = null;
        config.openDraftName = null;
        config.siblings = summaries(projectConfigs(projectId, null));
        config.approvers = approvers();
    }

    // Header and active rows of a stored configuration in the shape of the screens
    private static CommissionDto.Config toDto(Commission_Config__c record, Date today) {
        Map<String, CommissionDto.Designation> designations = CommissionCatalog.designationByKey();
        CommissionDto.Config config = new CommissionDto.Config();
        config.id = record.Id;
        config.name = record.Name;
        config.reference = record.Reference__c;
        config.version = whole(record.Version__c);
        config.projectId = record.Project__c;
        config.projectName = record.Project__r == null ? null : record.Project__r.Name;
        config.companyId = record.Project__r == null ? null : record.Project__r.Company__c;
        config.startDate = record.Start_Date__c;
        config.endDate = record.End_Date__c;
        config.originalEndDate = record.Original_End_Date__c;
        config.status = record.Status__c;
        config.state = stateOf(record, today);
        config.stateLabel = stateLabel(record, today);
        config.changeType = record.Change_Type__c;
        config.changeReason = record.Change_Reason__c;
        config.carryOverTargets = record.Carry_Over_Targets__c == true;
        config.priceExcludesTax = record.Price_Excludes_Tax__c == true;
        config.supersedesId = record.Supersedes__c;
        config.supersedesName = record.Supersedes__r == null ? null : record.Supersedes__r.Name;
        config.supersededById = record.Superseded_By__c;
        config.supersededByName = record.Superseded_By__r == null ? null : record.Superseded_By__r.Name;
        config.approverId = record.Approver__c;
        config.approverName = record.Approver__r == null ? null : record.Approver__r.Name;
        config.submittedById = record.Submitted_By__c;
        config.submittedByName = record.Submitted_By__r == null ? null : record.Submitted_By__r.Name;
        config.submittedOn = record.Submitted_On__c;
        config.approvedByName = record.Approved_By__r == null ? null : record.Approved_By__r.Name;
        config.approvedOn = record.Approved_On__c;
        config.decision = record.Decision__c;
        config.decisionComments = record.Decision_Comments__c;
        config.decisionByName = record.Decision_By__r == null ? null : record.Decision_By__r.Name;
        config.decisionOn = record.Decision_On__c;
        config.lastModified = latestTouch(record).at;

        // Rates: the paid designations from their rows, then every other designation of the catalog as "not paid"
        Map<String, Commission_Rate__c> paidByKey = new Map<String, Commission_Rate__c>();
        Map<String, String> splitByKey = new Map<String, String>();
        for (Commission_Rate__c row : record.Rates__r) {
            if (row.Designation__c == null) {
                continue;
            }
            if (row.Active__c == true) {
                paidByKey.put(row.Designation__c, row);
            }
            if (row.Active__c == true || !splitByKey.containsKey(row.Designation__c)) {
                splitByKey.put(row.Designation__c, row.Split__c);
            }
        }
        // The three options Finance sets once for every percentage rate
        String commonBasis = null;
        String commonPeriod = null;
        String commonMode = null;
        for (Commission_Rate__c row : paidByKey.values()) {
            if (row.Rate_Type__c != RATE_FLAT) {
                commonBasis = commonBasis == null ? row.Target_Basis__c : commonBasis;
                commonPeriod = commonPeriod == null ? row.Target_Period__c : commonPeriod;
                commonMode = commonMode == null ? row.Exceed_Mode__c : commonMode;
            }
        }
        config.rates = new List<CommissionDto.Rate>();
        Set<String> listed = new Set<String>();
        for (CommissionDto.Designation entry : CommissionCatalog.designations()) {
            listed.add(entry.key);
            Commission_Rate__c row = paidByKey.get(entry.key);
            if (row != null) {
                config.rates.add(rateDto(row, entry));
            } else {
                CommissionDto.Rate unpaid = unpaidRate(entry);
                if (unpaid.rateType != RATE_FLAT) {
                    unpaid.targetBasis = commonBasis;
                    unpaid.targetPeriod = commonPeriod;
                    unpaid.exceedMode = commonMode;
                }
                config.rates.add(unpaid);
            }
        }
        // A designation that was switched off in the catalog stays on the configurations that pay it
        for (Commission_Rate__c row : record.Rates__r) {
            if (row.Active__c == true && row.Designation__c != null && !listed.contains(row.Designation__c)) {
                config.rates.add(rateDto(row, null));
            }
        }

        // Stages: the shared ones and those of designations with their own release; a single fixed payout is not shown
        config.stages = new List<CommissionDto.Stage>();
        for (Commission_Stage__c row : record.Stages__r) {
            if (row.Active__c != true) {
                continue;
            }
            if (row.Designation__c != null) {
                String split = splitByKey.get(row.Designation__c);
                if (split == null && designations.containsKey(row.Designation__c)) {
                    split = designations.get(row.Designation__c).split;
                }
                if (split == SPLIT_SINGLE) {
                    continue;
                }
            }
            config.stages.add(stageDto(row));
        }
        return config;
    }

    private static CommissionDto.Stage stageDto(Commission_Stage__c row) {
        CommissionDto.Stage stage = new CommissionDto.Stage();
        stage.id = row.Id;
        stage.key = row.Id;
        stage.stageType = row.Stage_Type__c;
        stage.sequence = whole(row.Sequence__c);
        stage.triggerKey = row.Trigger__c;
        stage.triggerLabel = row.Trigger_Label__c;
        stage.parameterType = row.Parameter_Type__c;
        stage.triggerPercent = row.Trigger_Percent__c;
        stage.triggerTranche = whole(row.Trigger_Tranche__c);
        stage.installmentId = row.Trigger_Installment__c;
        stage.installmentName = row.Installment_Name__c;
        stage.releasePercent = row.Release_Percent__c;
        stage.designation = row.Designation__c;
        return stage;
    }

    private static CommissionDto.Rate rateDto(Commission_Rate__c row, CommissionDto.Designation entry) {
        CommissionDto.Rate rate = new CommissionDto.Rate();
        rate.id = row.Id;
        rate.key = row.Id;
        rate.designation = row.Designation__c;
        rate.label = row.Designation_Label__c != null ? row.Designation_Label__c : (entry == null ? row.Designation__c : entry.label);
        rate.paid = true;
        rate.rateType = row.Rate_Type__c != null ? row.Rate_Type__c : (entry == null ? null : entry.rateType);
        rate.currentRate = row.Current_Rate__c;
        rate.exceedRate = row.Exceed_Rate__c;
        rate.flatAmount = row.Flat_Amount__c;
        rate.target = row.Target__c;
        rate.targetBasis = row.Target_Basis__c;
        rate.targetPeriod = row.Target_Period__c;
        rate.exceedMode = row.Exceed_Mode__c;
        rate.split = row.Split__c != null ? row.Split__c : (entry == null ? null : entry.split);
        rate.releaseMode = row.Release_Mode__c;
        rate.contractReference = row.Contract_Reference__c;
        rate.targetRule = row.Target_Rule__c != null ? row.Target_Rule__c : (entry == null ? null : entry.targetRule);
        rate.claimLabel = row.Claim_Gate_Label__c != null ? row.Claim_Gate_Label__c : (entry == null ? null : entry.claimLabel);
        rate.aggregateOf = row.Aggregate_Of__c != null ? row.Aggregate_Of__c : (entry == null ? null : entry.aggregateOf);
        return rate;
    }

    // A designation of the catalog that is not paid: the screen shows it with its toggle off
    private static CommissionDto.Rate unpaidRate(CommissionDto.Designation entry) {
        CommissionDto.Rate rate = new CommissionDto.Rate();
        rate.key = entry.key;
        rate.designation = entry.key;
        rate.label = entry.label;
        rate.paid = false;
        rate.rateType = entry.rateType;
        rate.split = entry.split;
        rate.targetRule = entry.targetRule;
        rate.claimLabel = entry.claimLabel;
        rate.aggregateOf = entry.aggregateOf;
        return rate;
    }

    private static CommissionDto.Stage emptyStage(String stageType, Integer sequence) {
        CommissionDto.Stage stage = new CommissionDto.Stage();
        stage.key = newKey();
        stage.stageType = stageType;
        stage.sequence = sequence;
        return stage;
    }

    // A copy for another project cannot point at an instalment of a different company's payment schedule
    private static void blankForeignInstallments(List<CommissionDto.Stage> stages, Id companyId) {
        Set<Id> installmentIds = new Set<Id>();
        for (CommissionDto.Stage stage : stages) {
            if (stage.installmentId != null) {
                installmentIds.add(stage.installmentId);
            }
        }
        if (installmentIds.isEmpty()) {
            return;
        }
        Map<Id, Payment_Schedule_Master__c> masters = new Map<Id, Payment_Schedule_Master__c>([
            SELECT Id, Company__c FROM Payment_Schedule_Master__c WHERE Id IN :installmentIds WITH SYSTEM_MODE
        ]);
        for (CommissionDto.Stage stage : stages) {
            if (stage.installmentId == null) {
                continue;
            }
            Payment_Schedule_Master__c master = masters.get(stage.installmentId);
            if (master == null || master.Company__c != companyId) {
                stage.installmentId = null;
                stage.installmentName = null;
            }
        }
    }

    // What approving this version does, in one sentence
    private static String consequenceText(String changeType, Date startDate, Date endDate, Decimal earlierVersion, Date earlierEnd, String previousName) {
        if (changeType == CHANGE_CORRECTION && earlierVersion != null) {
            return String.format(COMMISSION_SERVICE_CONSEQUENCE_CORRECTION, new List<Object>{ wholeText(earlierVersion) });
        }
        if (changeType == CHANGE_FROM_DATE && earlierVersion != null && startDate != null) {
            return String.format(
                COMMISSION_SERVICE_CONSEQUENCE_FROM_DATE, new List<Object>{ formatDate(startDate), wholeText(earlierVersion) }
            );
        }
        if (changeType == CHANGE_END_EARLY && endDate != null && earlierEnd != null) {
            return String.format(
                COMMISSION_SERVICE_CONSEQUENCE_END_EARLY, new List<Object>{ formatDate(endDate), formatDate(earlierEnd) }
            );
        }
        if (changeType == CHANGE_NEXT_PERIOD && String.isNotBlank(previousName)) {
            return String.format(COMMISSION_SERVICE_CONSEQUENCE_NEXT_PERIOD, new List<Object>{ previousName });
        }
        return null;
    }

    // ------------------------------------------------------------ small helpers

    private static Touch latestTouch(Commission_Config__c record) {
        Touch latest = new Touch();
        latest.at = record.LastModifiedDate;
        latest.byName = record.LastModifiedBy == null ? null : record.LastModifiedBy.Name;
        for (Commission_Stage__c row : record.Stages__r) {
            if (latest.at == null || (row.LastModifiedDate != null && row.LastModifiedDate > latest.at)) {
                latest.at = row.LastModifiedDate;
                latest.byName = row.LastModifiedBy == null ? null : row.LastModifiedBy.Name;
            }
        }
        for (Commission_Rate__c row : record.Rates__r) {
            if (latest.at == null || (row.LastModifiedDate != null && row.LastModifiedDate > latest.at)) {
                latest.at = row.LastModifiedDate;
                latest.byName = row.LastModifiedBy == null ? null : row.LastModifiedBy.Name;
            }
        }
        return latest;
    }

    // The version that took this one's place, when the record carries it
    private static Decimal replacingVersion(Commission_Config__c record) {
        try {
            return record.Superseded_By__r == null ? null : record.Superseded_By__r.Version__c;
        } catch (SObjectException notQueried) {
            return null;
        }
    }

    // The lineage of a configuration; its own name while the reference has not been written
    private static String referenceOf(Commission_Config__c record) {
        return String.isBlank(record.Reference__c) ? record.Name : record.Reference__c;
    }

    private static Integer nextVersion(String reference) {
        List<AggregateResult> rows = [
            SELECT MAX(Version__c) highest FROM Commission_Config__c WHERE Reference__c = :reference WITH SYSTEM_MODE
        ];
        Decimal highest = rows.isEmpty() ? null : (Decimal) rows[0].get('highest');
        return highest == null ? 2 : highest.intValue() + 1;
    }

    // The last day of a period that starts on newStart and is as long as the given one: whole months stay whole months
    private static Date sameLength(Date startDate, Date endDate, Date newStart) {
        Integer months = startDate.monthsBetween(endDate.addDays(1));
        if (months > 0 && startDate.addMonths(months) == endDate.addDays(1)) {
            return newStart.addMonths(months).addDays(-1);
        }
        return newStart.addDays(startDate.daysBetween(endDate));
    }

    // The fields of a stored row that a save would change, as a record to update; null when nothing differs
    private static SObject changesOf(SObject fresh, SObject stored, List<Schema.SObjectField> fields) {
        SObject change = null;
        for (Schema.SObjectField field : fields) {
            Object value = fresh.get(field);
            if (!sameValue(value, stored.get(field))) {
                if (change == null) {
                    change = stored.getSObjectType().newSObject(stored.Id);
                }
                change.put(field, value);
            }
        }
        return change;
    }

    private static Boolean sameValue(Object left, Object right) {
        Object first = left instanceof String && String.isBlank((String) left) ? null : left;
        Object second = right instanceof String && String.isBlank((String) right) ? null : right;
        if (first == null || second == null) {
            return first == null && second == null;
        }
        Decimal firstNumber = numberOf(first);
        Decimal secondNumber = numberOf(second);
        if (firstNumber != null && secondNumber != null) {
            // 80 and 80.00 are the same value
            return firstNumber == secondNumber;
        }
        if (first instanceof String && second instanceof String) {
            // A text that only changed its capitals has changed
            return ((String) first).equals((String) second);
        }
        return first == second;
    }

    private static Decimal numberOf(Object value) {
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            Decimal asDecimal = (Integer) value;
            return asDecimal;
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        return null;
    }

    private static String clean(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static Decimal scaled(Decimal value, Integer places) {
        return value == null ? null : value.setScale(places, System.RoundingMode.HALF_UP);
    }

    private static Integer whole(Decimal value) {
        return value == null ? null : value.intValue();
    }

    private static String wholeText(Decimal value) {
        return value == null ? '' : String.valueOf(value.intValue());
    }

    private static String newKey() {
        keyCounter++;
        return 'new-' + keyCounter;
    }
}