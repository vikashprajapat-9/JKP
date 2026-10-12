// What the Targets view and the My terms view of Commission Setup call. The rules live in CommissionTargetService;
// this class only turns whatever goes wrong into a message the screen can show.
public without sharing class CommissionTargetController {

    // The target table of a project and configuration; both are optional (see CommissionTargetService.table)
    @AuraEnabled
    public static CommissionDto.TargetTable getTargets(Id projectId, String reference) {
        try {
            return CommissionTargetService.table(projectId, reference);
        } catch (Exception problem) {
            throw screenError(problem);
        }
    }

    // payload = JSON of CommissionDto.TargetSave: { projectId, reference, effectiveFrom, reason, changes: [{ userId, designation, target }] }
    @AuraEnabled
    public static CommissionDto.TargetTable saveTargets(String payload) {
        CommissionDto.TargetSave request;
        try {
            request = (CommissionDto.TargetSave) JSON.deserialize(payload, CommissionDto.TargetSave.class);
        } catch (Exception problem) {
            throw CommissionDto.error(Label.Commission_Target_Bad_Request);
        }
        try {
            return CommissionTargetService.save(request);
        } catch (Exception problem) {
            throw screenError(problem);
        }
    }

    // The running user's own terms; an empty list for someone who is not paid commission
    @AuraEnabled
    public static List<CommissionDto.MyTerm> getMyTerms() {
        try {
            return CommissionTargetService.myTerms();
        } catch (Exception problem) {
            throw screenError(problem);
        }
    }

    // A message of the services goes to the screen as it is, a rule of a trigger with its own text,
    // anything unexpected as the general message (the detail is in the debug log)
    private static AuraHandledException screenError(Exception problem) {
        if (problem instanceof AuraHandledException) {
            return (AuraHandledException) problem;
        }
        if (problem instanceof DmlException) {
            return CommissionDto.error(((DmlException) problem).getDmlMessage(0));
        }
        System.debug(LoggingLevel.ERROR, '>>> [Commission] ' + problem.getTypeName() + ': ' + problem.getMessage() + ' ' + problem.getStackTraceString());
        return CommissionDto.error(Label.Commission_Common_Error);
    }
}