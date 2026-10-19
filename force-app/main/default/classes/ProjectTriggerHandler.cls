public class ProjectTriggerHandler {

    // Creates the project's SharePoint folder. CreateSharePointFoldersQueueable then calls DocumentCreationHandler,
    // which creates a Document__c (and a sub-folder) for each category of the "Project" Document Master.
    public static void handleAfterInsert(List<Project__c> newProjects) {
        try {
            List<Id> projectIds = new List<Id>();
            for (Project__c proj : newProjects) {
                projectIds.add(proj.Id);
            }
            // Enqueueing past the limit throws an uncatchable LimitException that would roll back the project insert
            if (!projectIds.isEmpty() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new CreateSharePointFoldersQueueable(projectIds));
            }
        } catch (Exception e) {
            System.debug('Error in Project afterInsert: ' + e.getMessage() + ' at line: ' + e.getLineNumber());
        }
    }
}