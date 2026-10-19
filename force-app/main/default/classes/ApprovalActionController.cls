/**
 * Generic approval controller behind the c/approvalActionBar component.
 *
 * Works on ANY object that has an approval process, because everything is read
 * from the polymorphic approval objects (ProcessInstance.TargetObjectId).
 *
 * Runs "without sharing" so the component can READ approval data on any record,
 * but every action is explicitly authorised against the running user before the
 * standard Approval.process() API is called.
 */
public without sharing class ApprovalActionController {

    // ── Wrappers returned to the LWC ──────────────────────────────────────
    public class ApprovalState {
        @AuraEnabled public Boolean hasApproval    = false;   // record has been submitted at least once
        @AuraEnabled public Boolean isPending      = false;   // an approval is currently in flight
        @AuraEnabled public Boolean canAct         = false;   // running user is the current approver
        @AuraEnabled public Id      workItemId;               // the item the running user can act on
        @AuraEnabled public String  processName;
        @AuraEnabled public String  submittedByName;
        @AuraEnabled public Datetime submittedDate;
        @AuraEnabled public String  currentApproverName;
        @AuraEnabled public String  overallStatus;            // Pending | Approved | Rejected | Removed
        @AuraEnabled public List<StepInfo> steps = new List<StepInfo>();
    }

    public class StepInfo {
        @AuraEnabled public String   actorName;
        @AuraEnabled public String   stepStatus;   // Started | Approved | Rejected | Pending | Removed
        @AuraEnabled public String   comments;
        @AuraEnabled public Datetime actionDate;
        @AuraEnabled public Boolean  isPending  = false;
        @AuraEnabled public Boolean  isApproved = false;
        @AuraEnabled public Boolean  isRejected = false;
    }

    /**
     * Returns the approval state of a record for the running user.
     * Only the most recent approval process on the record is shown.
     */
    // Multi-level approvals in this org are built by CHAINING separate one-step
    // (usually ad-hoc) approval processes, so a single record can carry many
    // ProcessInstances. We therefore read them ALL - the pending work item may
    // sit on an older instance than the most recently created one.
    private static final Integer MAX_STEPS_SHOWN = 20;

    @AuraEnabled(cacheable=true)
    public static ApprovalState getApprovalState(Id recordId) {
        ApprovalState state = new ApprovalState();
        if (recordId == null) {
            return state;
        }

        List<ProcessInstance> instances = [
            SELECT Id, Status, CreatedDate, SubmittedById, SubmittedBy.Name, ProcessDefinition.Name,
                   (SELECT Id, StepStatus, Comments, ActorId, Actor.Name, CreatedDate,
                           OriginalActorId, OriginalActor.Name
                    FROM StepsAndWorkitems
                    ORDER BY CreatedDate ASC)
            FROM ProcessInstance
            WHERE TargetObjectId = :recordId
            ORDER BY CreatedDate ASC
        ];
        if (instances.isEmpty()) {
            return state;
        }

        state.hasApproval = true;
        // Submission details come from the first time the record entered approval.
        ProcessInstance first = instances[0];
        state.submittedByName = first.SubmittedBy != null ? first.SubmittedBy.Name : null;
        state.submittedDate   = first.CreatedDate;

        Set<Id> pendingInstanceIds = new Set<Id>();
        List<StepInfo> allSteps = new List<StepInfo>();
        ProcessInstance latestPending;

        for (ProcessInstance pi : instances) {
            if (pi.Status == 'Pending') {
                pendingInstanceIds.add(pi.Id);
                latestPending = pi;
            }
            for (ProcessInstanceHistory h : pi.StepsAndWorkitems) {
                // "Started" is the submission entry - surfaced separately as submittedBy.
                if (h.StepStatus == 'Started') {
                    continue;
                }
                StepInfo si   = new StepInfo();
                // When an approval is actioned from a Site, ActorId becomes the Site
                // Guest User. OriginalActor is the approver the request belongs to,
                // so that is the name worth showing.
                si.actorName  = (h.OriginalActor != null && String.isNotBlank(h.OriginalActor.Name))
                                ? h.OriginalActor.Name
                                : (h.Actor != null ? h.Actor.Name : null);
                si.stepStatus = h.StepStatus;
                si.comments   = h.Comments;
                si.actionDate = h.CreatedDate;
                si.isPending  = (h.StepStatus == 'Pending');
                si.isApproved = (h.StepStatus == 'Approved');
                si.isRejected = (h.StepStatus == 'Rejected');
                if (si.isPending) {
                    state.currentApproverName = si.actorName;
                }
                allSteps.add(si);
            }
        }

        state.isPending = !pendingInstanceIds.isEmpty();
        if (state.isPending) {
            state.overallStatus = 'Pending';
            state.processName   = latestPending != null && latestPending.ProcessDefinition != null
                                  ? latestPending.ProcessDefinition.Name : null;
        } else {
            // No approval in flight - report the outcome of the most recent one.
            ProcessInstance last = instances[instances.size() - 1];
            state.overallStatus = last.Status;
            state.processName   = last.ProcessDefinition != null ? last.ProcessDefinition.Name : null;
        }

        // Keep the trail readable on long chains - show the most recent activity.
        Integer startIndex = allSteps.size() > MAX_STEPS_SHOWN ? allSteps.size() - MAX_STEPS_SHOWN : 0;
        for (Integer i = startIndex; i < allSteps.size(); i++) {
            state.steps.add(allSteps[i]);
        }

        if (!state.isPending) {
            return state;
        }

        // Look for an outstanding work item across EVERY pending instance.
        for (ProcessInstanceWorkitem item : [
            SELECT Id, ActorId, OriginalActorId, ProcessInstance.ProcessDefinition.Name
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstanceId IN :pendingInstanceIds
        ]) {
            if (isActorForRunningUser(item.ActorId)) {
                state.canAct     = true;
                state.workItemId = item.Id;
                if (item.ProcessInstance != null && item.ProcessInstance.ProcessDefinition != null) {
                    state.processName = item.ProcessInstance.ProcessDefinition.Name;
                }
                break;
            }
        }
        return state;
    }

    /**
     * Approves or rejects using the STANDARD approval API, so the record's
     * approval history, field updates, email alerts and the next approval step
     * all behave exactly as they do from the standard Approve/Reject page.
     */
    @AuraEnabled
    public static String processAction(Id workItemId, String action, String comments) {
        if (workItemId == null) {
            throw new AuraHandledException('No approval request was found to act on.');
        }
        if (String.isBlank(action) || !(action == 'Approve' || action == 'Reject')) {
            throw new AuraHandledException('Please choose either Approve or Reject.');
        }
        if (String.isBlank(comments) || String.isBlank(comments.trim())) {
            throw new AuraHandledException('Please enter a comment before you ' + action.toLowerCase() + '.');
        }

        // Re-authorise on the server - never trust the client's canAct flag.
        List<ProcessInstanceWorkitem> items = [
            SELECT Id, ActorId FROM ProcessInstanceWorkitem WHERE Id = :workItemId LIMIT 1
        ];
        if (items.isEmpty()) {
            throw new AuraHandledException('This approval request has already been actioned by someone else.');
        }
        if (!isActorForRunningUser(items[0].ActorId)) {
            throw new AuraHandledException('This approval request is not assigned to you.');
        }

        try {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workItemId);
            req.setAction(action);
            req.setComments(comments.trim());
            Approval.ProcessResult result = Approval.process(req);

            if (!result.isSuccess()) {
                String msg = 'Unable to ' + action.toLowerCase() + ' this request.';
                if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                    msg = result.getErrors()[0].getMessage();
                }
                throw new AuraHandledException(msg);
            }
            return action == 'Approve' ? 'Approved' : 'Rejected';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Authorisation helpers ─────────────────────────────────────────────
    private static Set<Id> runningUserGroupIds;
    private static Set<Id> delegatedForUserIds;

    /**
     * True when the running user may act on a work item assigned to actorId:
     *   - the actor is the running user, or
     *   - the actor is a queue/group the running user belongs to, or
     *   - the running user is the actor's delegated approver.
     */
    private static Boolean isActorForRunningUser(Id actorId) {
        if (actorId == null) {
            return false;
        }
        Id runningUserId = UserInfo.getUserId();
        if (actorId == runningUserId) {
            return true;
        }
        String prefix = String.valueOf(actorId).substring(0, 3);
        if (prefix == '005') {
            return delegatedApproverFor().contains(actorId);
        }
        // 00G = Queue / public group
        return groupsOfRunningUser().contains(actorId);
    }

    private static Set<Id> groupsOfRunningUser() {
        if (runningUserGroupIds == null) {
            runningUserGroupIds = new Set<Id>();
            for (GroupMember gm : [
                SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :UserInfo.getUserId()
            ]) {
                runningUserGroupIds.add(gm.GroupId);
            }
        }
        return runningUserGroupIds;
    }

    private static Set<Id> delegatedApproverFor() {
        if (delegatedForUserIds == null) {
            delegatedForUserIds = new Set<Id>();
            for (User u : [
                SELECT Id FROM User WHERE DelegatedApproverId = :UserInfo.getUserId() AND IsActive = true
            ]) {
                delegatedForUserIds.add(u.Id);
            }
        }
        return delegatedForUserIds;
    }
}