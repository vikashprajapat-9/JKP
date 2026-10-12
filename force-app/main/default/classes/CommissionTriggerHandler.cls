// The rules behind the triggers of Commission Setup: who may change a configuration and its rows, how the status
// moves (only through the approval process), what is locked and who edited.
// The services switch the rules off for their own system steps with bypass, always in a try/finally.
public without sharing class CommissionTriggerHandler {

    public static Boolean bypass = false;

    private static final String STATUS_DRAFT = CommissionConfigValidator.DRAFT;
    private static final String STATUS_PENDING = CommissionConfigValidator.PENDING;
    private static final String STATUS_APPROVED = CommissionConfigValidator.APPROVED;
    private static final String STATUS_REJECTED = CommissionConfigValidator.REJECTED;
    private static final String STATUS_RECALLED = CommissionConfigValidator.RECALLED;

    // The two kinds of rows a configuration has
    private static final String OBJECT_STAGE = 'Payout Stage', OBJECT_RATE = 'Rate';

    // Status values of the approval records
    private static final String PROCESS_PENDING = 'Pending';
    // An approval request that is open: waiting for the approver, or just created by the submission that is running
    private static final Set<String> PROCESS_OPEN = new Set<String>{ PROCESS_PENDING, 'Started' };
    private static final String STEP_REJECTED = 'Rejected';
    private static final String STEP_STARTED = 'Started';

    // Events passed to the notifier
    private static final String NOTIFY_APPROVED = CommissionNotifier.APPROVED, NOTIFY_REJECTED = CommissionNotifier.REJECTED,
        NOTIFY_WITHDRAWN = CommissionNotifier.WITHDRAWN;

    // At most this many messages of an incomplete configuration are shown when it is submitted outside the screen
    private static final Integer MAX_MESSAGES = 5;
    private static final Integer EDITOR_FIELD_LENGTH = 4000;

    // The values of the catalog kept on each row, the same ones a save in Commission Setup writes
    private static final List<Schema.SObjectField> RATE_COPIES = new List<Schema.SObjectField>{
        Commission_Rate__c.Designation_Label__c, Commission_Rate__c.Rate_Type__c, Commission_Rate__c.Split__c,
        Commission_Rate__c.Target_Rule__c, Commission_Rate__c.Aggregate_Of__c, Commission_Rate__c.Claim_Gate__c,
        Commission_Rate__c.Claim_Gate_Label__c, Commission_Rate__c.Claim_Mode__c
    };
    private static final List<Schema.SObjectField> STAGE_COPIES = new List<Schema.SObjectField>{
        Commission_Stage__c.Trigger_Label__c, Commission_Stage__c.Detector__c, Commission_Stage__c.Parameter_Type__c
    };

    // Every field of the header a user or a process could write (read once per transaction)
    private static List<Schema.SObjectField> writableConfigFields;

    // ------------------------------------------------------------ entry points (one per trigger)

    public static void configs(System.TriggerOperation operation, List<Commission_Config__c> newRows, Map<Id, Commission_Config__c> oldMap) {
        switch on operation {
            when BEFORE_INSERT {
                beforeConfigInsert(newRows);
            }
            when AFTER_INSERT {
                afterConfigInsert(newRows);
            }
            when BEFORE_UPDATE {
                beforeConfigUpdate(newRows, oldMap);
            }
            when AFTER_UPDATE {
                afterConfigUpdate(newRows, oldMap);
            }
            when BEFORE_DELETE {
                beforeConfigDelete(oldMap.values());
            }
            when AFTER_UNDELETE {
                afterConfigUndelete(newRows);
            }
            when else {
                return;
            }
        }
    }

    public static void stages(System.TriggerOperation operation, List<Commission_Stage__c> newRows, Map<Id, Commission_Stage__c> oldMap) {
        children(operation, newRows, oldMap, OBJECT_STAGE);
    }

    public static void rates(System.TriggerOperation operation, List<Commission_Rate__c> newRows, Map<Id, Commission_Rate__c> oldMap) {
        children(operation, newRows, oldMap, OBJECT_RATE);
    }

    // ------------------------------------------------------------ the configuration (header)

    private static void beforeConfigInsert(List<Commission_Config__c> rows) {
        Boolean allowed = bypass || CommissionAccess.can(CommissionAccess.CONFIGURE);
        for (Commission_Config__c row : rows) {
            if (!allowed) {
                row.addError(System.Label.Commission_Rule_Configure_Only);
                continue;
            }
            if (row.Version__c == null || row.Version__c < 1) {
                row.Version__c = 1;
            }
            if (String.isBlank(row.Change_Type__c)) {
                row.Change_Type__c = CommissionConfigValidator.CHANGE_NEW;
            }
            if (bypass) {
                // A service may write any state; only what is missing is filled in
                if (String.isBlank(row.Status__c)) {
                    row.Status__c = STATUS_DRAFT;
                }
                if (String.isBlank(row.Version_Key__c) && String.isNotBlank(row.Reference__c)) {
                    row.Version_Key__c = versionKey(row.Reference__c, row.Version__c);
                }
                continue;
            }
            // Whatever was sent, a configuration starts as a draft nobody has submitted or decided
            row.Status__c = STATUS_DRAFT;
            row.Submitted_By__c = null;
            row.Submitted_On__c = null;
            row.Approved_By__c = null;
            row.Approved_On__c = null;
            row.Decision__c = null;
            row.Decision_By__c = null;
            row.Decision_On__c = null;
            row.Decision_Comments__c = null;
            row.Superseded_By__c = null;
            row.Original_End_Date__c = null;
            row.Editor_Ids__c = String.valueOf(UserInfo.getUserId());
            row.Version_Key__c = String.isBlank(row.Reference__c) ? null : versionKey(row.Reference__c, row.Version__c);
        }
    }

    private static void afterConfigInsert(List<Commission_Config__c> rows) {
        // A first version is its own lineage: the reference is its Name, known only now
        List<Commission_Config__c> keyed = new List<Commission_Config__c>();
        for (Commission_Config__c row : rows) {
            String reference = String.isBlank(row.Reference__c) ? row.Name : row.Reference__c;
            if (String.isBlank(row.Reference__c) || String.isBlank(row.Version_Key__c)) {
                keyed.add(new Commission_Config__c(
                    Id = row.Id, Reference__c = reference, Version_Key__c = versionKey(reference, row.Version__c)
                ));
            }
        }
        if (!keyed.isEmpty()) {
            systemUpdate(keyed);
        }
    }

    private static void beforeConfigUpdate(List<Commission_Config__c> rows, Map<Id, Commission_Config__c> oldMap) {
        if (bypass) {
            return;
        }
        Boolean canConfigure = CommissionAccess.can(CommissionAccess.CONFIGURE);
        List<Commission_Config__c> submitted = new List<Commission_Config__c>();
        List<Commission_Config__c> approved = new List<Commission_Config__c>();
        List<Commission_Config__c> rejected = new List<Commission_Config__c>();
        List<Commission_Config__c> recalled = new List<Commission_Config__c>();
        for (Commission_Config__c row : rows) {
            Commission_Config__c old = oldMap.get(row.Id);
            if (row.Status__c == old.Status__c) {
                if (old.Status__c == STATUS_DRAFT) {
                    if (!canConfigure) {
                        row.addError(System.Label.Commission_Rule_Configure_Only);
                    } else if (old.Supersedes__c != null && row.Project__c != old.Project__c) {
                        // A new version stays with the project of the version it was made from
                        row.addError(System.Label.Commission_Rule_Project_Fixed);
                    } else {
                        row.Editor_Ids__c = withEditor(row.Editor_Ids__c, UserInfo.getUserId());
                    }
                } else if (anyFieldChanged(row, old)) {
                    row.addError(lockedMessage(old.Status__c));
                }
            } else if (old.Status__c == STATUS_DRAFT && row.Status__c == STATUS_PENDING) {
                submitted.add(row);
            } else if (old.Status__c == STATUS_PENDING && row.Status__c == STATUS_APPROVED) {
                approved.add(row);
            } else if (old.Status__c == STATUS_PENDING && row.Status__c == STATUS_REJECTED) {
                rejected.add(row);
            } else if (old.Status__c == STATUS_PENDING && row.Status__c == STATUS_RECALLED) {
                recalled.add(row);
            } else {
                row.addError(System.Label.Commission_Rule_Status_Change);
            }
        }
        if (!submitted.isEmpty()) {
            onSubmit(submitted);
        }
        if (!approved.isEmpty()) {
            onApprove(approved);
        }
        if (!rejected.isEmpty()) {
            onReject(rejected);
        }
        if (!recalled.isEmpty()) {
            onRecall(recalled);
        }
    }

    // Draft -> Pending Approval, written by the approval process when Finance submits
    private static void onSubmit(List<Commission_Config__c> rows) {
        if (!CommissionAccess.can(CommissionAccess.CONFIGURE)) {
            refuseAll(rows, System.Label.Commission_Rule_Configure_Only);
            return;
        }
        Set<Id> ids = new Set<Id>();
        Set<Id> approverIds = new Set<Id>();
        for (Commission_Config__c row : rows) {
            ids.add(row.Id);
            if (row.Approver__c != null) {
                approverIds.add(row.Approver__c);
            }
        }
        // The status may only move as part of an approval request, never by a plain edit
        Set<Id> inProcess = new Set<Id>();
        for (ProcessInstance request : [
            SELECT TargetObjectId FROM ProcessInstance WHERE TargetObjectId IN :ids AND Status IN :PROCESS_OPEN WITH SYSTEM_MODE
        ]) {
            inProcess.add(request.TargetObjectId);
        }
        Map<Id, List<Commission_Stage__c>> stagesByConfig = new Map<Id, List<Commission_Stage__c>>();
        for (Commission_Stage__c stage : [
            SELECT Id, Config__c, Stage_Type__c, Sequence__c, Trigger__c, Parameter_Type__c, Trigger_Percent__c,
                   Trigger_Tranche__c, Trigger_Installment__c, Release_Percent__c, Designation__c, Active__c
            FROM Commission_Stage__c
            WHERE Config__c IN :ids AND Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Sequence__c, Name
        ]) {
            if (!stagesByConfig.containsKey(stage.Config__c)) {
                stagesByConfig.put(stage.Config__c, new List<Commission_Stage__c>());
            }
            stagesByConfig.get(stage.Config__c).add(stage);
        }
        Map<Id, List<Commission_Rate__c>> ratesByConfig = new Map<Id, List<Commission_Rate__c>>();
        for (Commission_Rate__c rate : [
            SELECT Id, Config__c, Designation__c, Designation_Label__c, Rate_Type__c, Split__c, Target_Rule__c, Release_Mode__c,
                   Current_Rate__c, Exceed_Rate__c, Flat_Amount__c, Target__c, Target_Basis__c, Target_Period__c,
                   Exceed_Mode__c, Active__c
            FROM Commission_Rate__c
            WHERE Config__c IN :ids AND Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Name
        ]) {
            if (!ratesByConfig.containsKey(rate.Config__c)) {
                ratesByConfig.put(rate.Config__c, new List<Commission_Rate__c>());
            }
            ratesByConfig.get(rate.Config__c).add(rate);
        }
        Set<Id> activeApprovers = approverIds.isEmpty()
            ? new Set<Id>()
            : new Map<Id, User>([SELECT Id FROM User WHERE Id IN :approverIds AND IsActive = true WITH SYSTEM_MODE]).keySet();

        Id me = UserInfo.getUserId();
        Datetime moment = System.now();
        for (Commission_Config__c row : rows) {
            if (!inProcess.contains(row.Id) && !isLocked(row.Id)) {
                row.addError(System.Label.Commission_Rule_Use_Submit);
                continue;
            }
            List<CommissionDto.Issue> issues = CommissionConfigValidator.checkRecords(
                row, stagesByConfig.get(row.Id), ratesByConfig.get(row.Id), true
            );
            if (!issues.isEmpty()) {
                row.addError(CommissionConfigValidator.fill(System.Label.Commission_Rule_Not_Complete, new List<Object>{ messagesOf(issues) }));
                continue;
            }
            if (row.Approver__c == null || !activeApprovers.contains(row.Approver__c)) {
                row.addError(System.Label.Commission_Rule_Approver_Required);
                continue;
            }
            row.Submitted_By__c = me;
            row.Submitted_On__c = moment;
            row.Decision__c = null;
            row.Decision_By__c = null;
            row.Decision_On__c = null;
            row.Decision_Comments__c = null;
        }
    }

    // Pending Approval -> Approved, written by the approval process when the approver approves
    private static void onApprove(List<Commission_Config__c> rows) {
        if (!CommissionAccess.can(CommissionAccess.APPROVE)) {
            refuseAll(rows, System.Label.Commission_Rule_Approve_Only);
            return;
        }
        // One approval per project at a time, so that two approvals cannot both pass the overlap check
        Set<Id> projectIds = new Set<Id>();
        for (Commission_Config__c row : rows) {
            if (row.Project__c != null) {
                projectIds.add(row.Project__c);
            }
        }
        try {
            List<SObject> held = Database.query('SELECT Id FROM Project__c WHERE Id IN :projectIds FOR UPDATE', AccessLevel.SYSTEM_MODE);
        } catch (QueryException busy) {
            refuseAll(rows, System.Label.Commission_Rule_Approval_Busy);
            return;
        }

        Boolean selfApproval = CommissionAccess.selfApprovalAllowed();
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        Datetime moment = System.now();
        for (Commission_Config__c row : rows) {
            // Whoever entered or edited the figures does not approve them
            if (!selfApproval && (hasEditor(row.Editor_Ids__c, me) || row.Submitted_By__c == me || row.CreatedById == me)) {
                row.addError(System.Label.Commission_Rule_Self_Approval);
                continue;
            }
            CommissionDto.Summary clash = CommissionConfigValidator.overlapWith(row);
            if (clash != null) {
                row.addError(CommissionConfigValidator.overlapMessage(clash));
                continue;
            }
            // A change that waited too long would rewrite days that have already passed
            if (row.Change_Type__c == CommissionConfigValidator.CHANGE_FROM_DATE && row.Start_Date__c != null && row.Start_Date__c < today) {
                row.addError(CommissionConfigValidator.fill(System.Label.Commission_Rule_Start_Passed, new List<Object>{ row.Start_Date__c }));
                continue;
            }
            if (row.Change_Type__c == CommissionConfigValidator.CHANGE_END_EARLY && row.End_Date__c != null && row.End_Date__c < today) {
                row.addError(CommissionConfigValidator.fill(System.Label.Commission_Rule_End_Passed, new List<Object>{ row.End_Date__c }));
                continue;
            }
            row.Approved_By__c = me;
            row.Approved_On__c = moment;
        }
    }

    // Pending Approval -> Rejected, written by the approval process. The record goes back to Draft in the same save.
    private static void onReject(List<Commission_Config__c> rows) {
        if (!CommissionAccess.can(CommissionAccess.APPROVE)) {
            refuseAll(rows, System.Label.Commission_Rule_Approve_Only);
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Commission_Config__c row : rows) {
            ids.add(row.Id);
        }
        Map<Id, String> comments = rejectionComments(ids);
        Id me = UserInfo.getUserId();
        Datetime moment = System.now();
        for (Commission_Config__c row : rows) {
            String comment = comments.get(row.Id);
            if (String.isBlank(comment)) {
                row.addError(System.Label.Commission_Rule_Reject_Comment);
                continue;
            }
            row.Decision_Comments__c = comment.trim().abbreviate(EDITOR_FIELD_LENGTH);
            row.Decision__c = STATUS_REJECTED;
            row.Decision_By__c = me;
            row.Decision_On__c = moment;
            row.Status__c = STATUS_DRAFT;
        }
    }

    // Pending Approval -> Recalled, written by the approval process when the submitter withdraws. Back to Draft.
    private static void onRecall(List<Commission_Config__c> rows) {
        if (!CommissionAccess.can(CommissionAccess.CONFIGURE)) {
            refuseAll(rows, System.Label.Commission_Rule_Configure_Only);
            return;
        }
        Id me = UserInfo.getUserId();
        Datetime moment = System.now();
        for (Commission_Config__c row : rows) {
            row.Decision_Comments__c = null;
            row.Decision__c = STATUS_RECALLED;
            row.Decision_By__c = me;
            row.Decision_On__c = moment;
            row.Status__c = STATUS_DRAFT;
        }
    }

    private static void afterConfigUpdate(List<Commission_Config__c> rows, Map<Id, Commission_Config__c> oldMap) {
        if (bypass) {
            return;
        }
        List<Commission_Config__c> approved = new List<Commission_Config__c>();
        Set<Id> approvedIds = new Set<Id>();
        Set<Id> rejectedIds = new Set<Id>();
        Set<Id> withdrawnIds = new Set<Id>();
        for (Commission_Config__c row : rows) {
            Commission_Config__c old = oldMap.get(row.Id);
            if (old.Status__c == STATUS_PENDING && row.Status__c == STATUS_APPROVED) {
                approved.add(row);
                approvedIds.add(row.Id);
            } else if (old.Status__c == STATUS_PENDING && row.Status__c == STATUS_DRAFT && row.Decision__c == STATUS_REJECTED) {
                rejectedIds.add(row.Id);
            } else if (old.Status__c == STATUS_PENDING && row.Status__c == STATUS_DRAFT) {
                withdrawnIds.add(row.Id);
            }
        }
        if (!approved.isEmpty()) {
            // The earlier version is replaced or shortened, personal targets move on to a next period
            CommissionConfigService.afterApproval(approved);
            CommissionNotifier.enqueue(NOTIFY_APPROVED, approvedIds);
        }
        if (!rejectedIds.isEmpty()) {
            CommissionNotifier.enqueue(NOTIFY_REJECTED, rejectedIds);
        }
        if (!withdrawnIds.isEmpty()) {
            CommissionNotifier.enqueue(NOTIFY_WITHDRAWN, withdrawnIds);
        }
    }

    // Only a draft can be deleted
    private static void beforeConfigDelete(List<Commission_Config__c> rows) {
        if (bypass) {
            return;
        }
        Boolean canConfigure = CommissionAccess.can(CommissionAccess.CONFIGURE);
        for (Commission_Config__c row : rows) {
            if (!canConfigure) {
                row.addError(System.Label.Commission_Rule_Configure_Only);
            } else if (row.Status__c != STATUS_DRAFT) {
                row.addError(lockedMessage(row.Status__c));
            }
        }
    }

    // A restore from the Recycle Bin follows the rules of a change: only Finance, and only a draft
    private static void afterConfigUndelete(List<Commission_Config__c> rows) {
        if (bypass) {
            return;
        }
        Boolean canConfigure = CommissionAccess.can(CommissionAccess.CONFIGURE);
        Boolean anyRefused = false;
        for (Commission_Config__c row : rows) {
            if (!canConfigure) {
                row.addError(System.Label.Commission_Rule_Configure_Only);
                anyRefused = true;
            } else if (row.Status__c != STATUS_DRAFT) {
                row.addError(lockedMessage(row.Status__c));
                anyRefused = true;
            }
        }
        if (anyRefused) {
            return;
        }
        // Whoever restored has edited the configuration
        Id me = UserInfo.getUserId();
        List<Commission_Config__c> edited = new List<Commission_Config__c>();
        for (Commission_Config__c row : rows) {
            if (!hasEditor(row.Editor_Ids__c, me)) {
                edited.add(new Commission_Config__c(Id = row.Id, Editor_Ids__c = withEditor(row.Editor_Ids__c, me)));
            }
        }
        if (!edited.isEmpty()) {
            systemUpdate(edited);
        }
    }

    // ------------------------------------------------------------ payout stages and rates (rows of a configuration)

    private static void children(System.TriggerOperation operation, List<SObject> newRows, Map<Id, SObject> oldMap, String objectName) {
        if (bypass) {
            return;
        }
        Boolean isDelete = operation == System.TriggerOperation.BEFORE_DELETE || operation == System.TriggerOperation.AFTER_DELETE;
        Boolean isBefore = operation == System.TriggerOperation.BEFORE_INSERT || operation == System.TriggerOperation.BEFORE_UPDATE
            || operation == System.TriggerOperation.BEFORE_DELETE;
        // A row restored from the Recycle Bin is checked like a change
        Boolean isRestore = operation == System.TriggerOperation.AFTER_UNDELETE;
        List<SObject> rows = isDelete ? oldMap.values() : newRows;
        if (rows == null || rows.isEmpty()) {
            return;
        }
        Set<Id> configIds = new Set<Id>();
        for (SObject row : rows) {
            Id configId = (Id) row.get('Config__c');
            if (configId != null) {
                configIds.add(configId);
            }
        }
        Map<Id, Commission_Config__c> parents = new Map<Id, Commission_Config__c>([
            SELECT Id, Status__c, Editor_Ids__c
            FROM Commission_Config__c
            WHERE Id IN :configIds
            WITH SYSTEM_MODE
        ]);

        if (isBefore || isRestore) {
            // Rows follow their configuration: only Finance, and only while it is a draft
            Boolean canConfigure = CommissionAccess.can(CommissionAccess.CONFIGURE);
            // A row that is added or edited also follows the catalog
            Boolean isWrite = isBefore && !isDelete && canConfigure;
            Boolean isRate = objectName == OBJECT_RATE;
            Map<String, CommissionDto.Designation> designations = isWrite && isRate ? CommissionCatalog.designationByKey() : null;
            Map<String, CommissionDto.TriggerOption> payoutEvents = isWrite && !isRate ? CommissionCatalog.triggerByKey() : null;
            Boolean anyRefused = false;
            for (SObject row : rows) {
                Commission_Config__c parent = parents.get((Id) row.get('Config__c'));
                String problem = null;
                if (!canConfigure) {
                    problem = System.Label.Commission_Rule_Configure_Only;
                } else if (parent != null && parent.Status__c != STATUS_DRAFT) {
                    problem = lockedMessage(parent.Status__c);
                } else if (isWrite) {
                    SObject old = oldMap == null ? null : oldMap.get(row.Id);
                    problem = isRate ? rateFollowsCatalog(row, old, designations) : stageFollowsCatalog(row, old, payoutEvents);
                }
                if (problem != null) {
                    row.addError(problem);
                    anyRefused = true;
                }
            }
            // A restore that is refused makes nobody an editor
            if (isBefore || anyRefused) {
                return;
            }
        }

        // Whoever changed a row has edited the configuration
        Id me = UserInfo.getUserId();
        List<Commission_Config__c> edited = new List<Commission_Config__c>();
        for (Commission_Config__c parent : parents.values()) {
            if (!hasEditor(parent.Editor_Ids__c, me)) {
                edited.add(new Commission_Config__c(Id = parent.Id, Editor_Ids__c = withEditor(parent.Editor_Ids__c, me)));
            }
        }
        if (!edited.isEmpty()) {
            systemUpdate(edited);
        }
    }

    // A rate is for a designation of the catalog and carries the catalog's values, as a save in Commission Setup writes
    // them. A designation the row already had stays when it has left the catalog, with the values the row has.
    // Returns what is wrong, or null.
    private static String rateFollowsCatalog(SObject row, SObject old, Map<String, CommissionDto.Designation> designations) {
        String key = (String) row.get(Commission_Rate__c.Designation__c);
        if (String.isBlank(key)) {
            return System.Label.Commission_Rule_Designation_Required;
        }
        CommissionDto.Designation entry = designations.get(key);
        if (entry == null) {
            if (old == null || !key.equals((String) old.get(Commission_Rate__c.Designation__c))) {
                return CommissionConfigValidator.fill(System.Label.Commission_Rule_Designation_Invalid, new List<Object>{ key });
            }
            keepCopies(row, old, RATE_COPIES);
            return null;
        }
        row.put(Commission_Rate__c.Designation_Label__c, entry.label);
        row.put(Commission_Rate__c.Rate_Type__c, entry.rateType);
        row.put(Commission_Rate__c.Split__c, entry.split);
        row.put(Commission_Rate__c.Target_Rule__c, entry.targetRule);
        row.put(Commission_Rate__c.Aggregate_Of__c, entry.aggregateOf);
        row.put(Commission_Rate__c.Claim_Gate__c, entry.claimGate);
        row.put(Commission_Rate__c.Claim_Gate_Label__c, entry.claimLabel);
        row.put(Commission_Rate__c.Claim_Mode__c, entry.claimMode);
        return null;
    }

    // The same for the payout event of a stage. A stage may still be without an event: a draft can be incomplete.
    private static String stageFollowsCatalog(SObject row, SObject old, Map<String, CommissionDto.TriggerOption> payoutEvents) {
        String key = (String) row.get(Commission_Stage__c.Trigger__c);
        if (String.isBlank(key)) {
            for (Schema.SObjectField field : STAGE_COPIES) {
                row.put(field, null);
            }
            return null;
        }
        CommissionDto.TriggerOption option = payoutEvents.get(key);
        if (option == null) {
            if (old == null || !key.equals((String) old.get(Commission_Stage__c.Trigger__c))) {
                return CommissionConfigValidator.fill(System.Label.Commission_Rule_Stage_Trigger_Invalid, new List<Object>{
                    CommissionConfigValidator.stageName((String) row.get(Commission_Stage__c.Stage_Type__c), null,
                        (String) row.get(Commission_Stage__c.Designation__c))
                });
            }
            keepCopies(row, old, STAGE_COPIES);
            return null;
        }
        row.put(Commission_Stage__c.Trigger_Label__c, option.label);
        row.put(Commission_Stage__c.Detector__c, option.detector);
        row.put(Commission_Stage__c.Parameter_Type__c, option.parameterType);
        return null;
    }

    private static void keepCopies(SObject row, SObject old, List<Schema.SObjectField> fields) {
        for (Schema.SObjectField field : fields) {
            row.put(field, old.get(field));
        }
    }

    // ------------------------------------------------------------ helpers

    // Updates made by the handler itself are system steps: the rules do not run on them
    private static void systemUpdate(List<SObject> rows) {
        Boolean bypassBefore = bypass;
        bypass = true;
        try {
            update as system rows;
        } finally {
            bypass = bypassBefore;
        }
    }

    private static void refuseAll(List<Commission_Config__c> rows, String message) {
        for (Commission_Config__c row : rows) {
            row.addError(message);
        }
    }

    private static String lockedMessage(String status) {
        return status == STATUS_PENDING ? System.Label.Commission_Rule_Pending_Locked : System.Label.Commission_Rule_Approved_Locked;
    }

    private static String versionKey(String reference, Decimal version) {
        return reference + '-v' + (version == null ? 1 : version.intValue());
    }

    // The latest rejection comment of each record: the step with status Rejected of its latest approval request
    private static Map<Id, String> rejectionComments(Set<Id> ids) {
        Map<Id, String> comments = new Map<Id, String>();
        Set<Id> seen = new Set<Id>();
        for (ProcessInstance request : [
            SELECT Id, TargetObjectId,
                   (SELECT Id, StepStatus, Comments FROM Steps ORDER BY CreatedDate DESC, Id DESC)
            FROM ProcessInstance
            WHERE TargetObjectId IN :ids
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC, Id DESC
        ]) {
            // Only the latest request of a record counts
            if (seen.contains(request.TargetObjectId)) {
                continue;
            }
            seen.add(request.TargetObjectId);
            String fallback = null;
            Boolean found = false;
            for (ProcessInstanceStep step : request.Steps) {
                if (step.StepStatus == STEP_REJECTED) {
                    comments.put(request.TargetObjectId, step.Comments);
                    found = true;
                    break;
                }
                if (fallback == null && step.StepStatus != STEP_STARTED) {
                    fallback = step.Comments;
                }
            }
            if (!found && fallback != null) {
                comments.put(request.TargetObjectId, fallback);
            }
        }
        return comments;
    }

    // A record in an approval request is locked by the platform
    private static Boolean isLocked(Id recordId) {
        try {
            return Approval.isLocked(recordId);
        } catch (Exception unknown) {
            return false;
        }
    }

    // The first messages of an incomplete configuration, in one line
    private static String messagesOf(List<CommissionDto.Issue> issues) {
        List<String> messages = new List<String>();
        for (CommissionDto.Issue issue : issues) {
            if (String.isNotBlank(issue.message) && !messages.contains(issue.message) && messages.size() < MAX_MESSAGES) {
                messages.add(issue.message);
            }
        }
        return String.join(messages, ' ');
    }

    // The first 15 characters are enough: an id written in its short form is found too
    private static Boolean hasEditor(String editorIds, Id userId) {
        return String.isNotBlank(editorIds) && userId != null && editorIds.contains(String.valueOf(userId).left(15));
    }

    // The 18-character ids of everyone who edited, comma separated
    private static String withEditor(String editorIds, Id userId) {
        if (userId == null || hasEditor(editorIds, userId)) {
            return editorIds;
        }
        String id18 = String.valueOf(userId);
        if (String.isBlank(editorIds)) {
            return id18;
        }
        // A full field keeps what it has
        return editorIds.length() + id18.length() + 1 > EDITOR_FIELD_LENGTH ? editorIds : editorIds + ',' + id18;
    }

    // True when an update of a locked configuration would change something
    private static Boolean anyFieldChanged(Commission_Config__c row, Commission_Config__c old) {
        if (writableConfigFields == null) {
            writableConfigFields = new List<Schema.SObjectField>();
            for (Schema.SObjectField field : Schema.SObjectType.Commission_Config__c.fields.getMap().values()) {
                Schema.DescribeFieldResult about = field.getDescribe();
                if (about.isCustom() && !about.isCalculated()) {
                    writableConfigFields.add(field);
                }
            }
        }
        for (Schema.SObjectField field : writableConfigFields) {
            Object was = old.get(field);
            Object isNow = row.get(field);
            if (was == null || isNow == null) {
                if (was != null || isNow != null) {
                    return true;
                }
            } else if (was instanceof String) {
                if (!((String) was).equals(String.valueOf(isNow))) {
                    return true;
                }
            } else if (was != isNow) {
                return true;
            }
        }
        return false;
    }
}