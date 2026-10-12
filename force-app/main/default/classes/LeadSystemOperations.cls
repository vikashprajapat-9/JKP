// The two operations the lead logic needs that are refused in a portal partner's context at API 67 (where Apex runs
// in user mode): publishing the lead platform events and submitting approval requests. This class is API 64 and
// without sharing, so they run in system mode whoever saves the lead. The rules themselves are in LeadLogicController.
public without sharing class LeadSystemOperations {

    public static List<Database.SaveResult> publish(List<SObject> events) {
        return EventBus.publish(events);
    }

    public static List<Approval.ProcessResult> submitForApproval(List<Approval.ProcessSubmitRequest> submissions) {
        if (submissions.isEmpty()) {
            return new List<Approval.ProcessResult>();
        }
        return Approval.process(submissions, false);
    }
}