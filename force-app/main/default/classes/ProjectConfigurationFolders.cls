// One SharePoint folder per Project Configuration:
//   <project folder> / Project Configurations / "<Configuration Number> - <Project Name> - <Unit Type>"
// Folders are Document__c records. CreateSharePointFoldersQueueable creates them in SharePoint inside the Parent
// Document's folder, the same way it creates the Document Master folders, and files uploaded for the
// configuration are saved into that folder as Sub Documents.
public without sharing class ProjectConfigurationFolders {

    public static final String PARENT_FOLDER = 'Project Configurations';
    // Document names hold 80 characters
    private static final Integer MAX_NAME = 80;
    // A folder still missing in SharePoint this long after its Document was created counts as stalled
    // (the folder job normally takes about a second per folder)
    private static final Integer STALLED_AFTER_SECONDS = 45;
    private static final Set<String> PENDING_JOB_STATUSES = new Set<String>{ 'Holding', 'Queued', 'Preparing', 'Processing' };

    // Lets a test make the folder step fail after the parent folders were inserted
    @TestVisible
    private static Boolean simulateFailure = false;
    // The Document ids of the last folder job queued in this transaction
    @TestVisible
    private static List<Id> lastQueued = new List<Id>();

    // Trigger entry point. A folder problem must never stop the configuration itself from being saved.
    public static void handleAfterInsert(Map<Id, Project_Configuration__c> newConfigurations) {
        Savepoint beforeFolders = Database.setSavepoint();
        try {
            createFolders(newConfigurations.keySet());
        } catch (Exception e) {
            Database.rollback(beforeFolders);
            System.debug(LoggingLevel.ERROR, 'Project configuration folders were not created: ' + e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    // Creates the missing folders of these configurations and queues their creation in SharePoint.
    public static void createFolders(Set<Id> configurationIds) {
        FolderPlan plan = planFolders(configurationIds);
        enqueue(plan.documentIds, plan.parentStillPending);
    }

    // Used when the component needs a configuration's folder: creates it if it is missing, and queues again a
    // folder whose SharePoint creation failed or was skipped. That only happens while no folder job is pending,
    // so SharePoint never receives the same folder twice.
    public static void ensureFolders(Set<Id> configurationIds) {
        List<Id> documentIds = folderJobPending() ? new List<Id>() : stalledFolders(configurationIds);
        FolderPlan plan = planFolders(configurationIds);
        documentIds.addAll(plan.documentIds);
        enqueue(documentIds, plan.parentStillPending);
    }

    private class FolderPlan {
        List<Id> documentIds = new List<Id>();
        // An existing "Project Configurations" Document whose SharePoint folder another job is still creating
        Boolean parentStillPending = false;
    }

    // Adds a Document__c for each configuration that has none yet, plus the project's "Project Configurations"
    // Document__c when the project has none. The new Document ids come back with the parent folders first, so
    // SharePoint creates them before the folders that go inside them. A project whose own SharePoint folder does not
    // exist yet (it was created seconds ago) is left for later: ensureFolders adds its folders once it does.
    private static FolderPlan planFolders(Set<Id> configurationIds) {
        FolderPlan plan = new FolderPlan();
        if (configurationIds == null || configurationIds.isEmpty()) {
            return plan;
        }
        Set<Id> withFolder = new Set<Id>();
        for (Document__c folder : [
            SELECT Project_Configuration__c
            FROM Document__c
            WHERE Project_Configuration__c IN :configurationIds
            WITH SYSTEM_MODE
        ]) {
            withFolder.add(folder.Project_Configuration__c);
        }

        List<Project_Configuration__c> configurations = new List<Project_Configuration__c>();
        Set<Id> projectIds = new Set<Id>();
        for (Project_Configuration__c config : [
            SELECT Id, Name, Unit_Type__c, Project__c, Project__r.Name, Project__r.Document_Id__c
            FROM Project_Configuration__c
            WHERE Id IN :configurationIds AND Project__c != null
            WITH SYSTEM_MODE
            ORDER BY Name
        ]) {
            if (!withFolder.contains(config.Id) && String.isNotBlank(config.Project__r.Document_Id__c)) {
                configurations.add(config);
                projectIds.add(config.Project__c);
            }
        }
        if (configurations.isEmpty()) {
            return plan;
        }

        // The oldest "Project Configurations" that already exists in SharePoint, else the oldest one
        Map<Id, Document__c> parentByProject = new Map<Id, Document__c>();
        for (Document__c parent : [
            SELECT Id, Project__c, Document_Id__c
            FROM Document__c
            WHERE Project__c IN :projectIds AND Name = :PARENT_FOLDER
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            Document__c chosen = parentByProject.get(parent.Project__c);
            if (chosen == null || (String.isBlank(chosen.Document_Id__c) && String.isNotBlank(parent.Document_Id__c))) {
                parentByProject.put(parent.Project__c, parent);
            }
        }
        List<Document__c> newParents = new List<Document__c>();
        for (Id projectId : projectIds) {
            Document__c parent = parentByProject.get(projectId);
            if (parent == null) {
                parent = new Document__c(Name = PARENT_FOLDER, Project__c = projectId);
                parentByProject.put(projectId, parent);
                newParents.add(parent);
            } else if (String.isBlank(parent.Document_Id__c)) {
                plan.parentStillPending = true;
            }
        }
        Database.insert(newParents, AccessLevel.SYSTEM_MODE);
        if (simulateFailure) {
            throw new DmlException('Simulated folder failure');
        }

        // No Project__c on these, so they are listed inside Project Configurations rather than beside it
        List<Document__c> folders = new List<Document__c>();
        for (Project_Configuration__c config : configurations) {
            folders.add(new Document__c(
                Name = folderName(config),
                Parent_Document__c = parentByProject.get(config.Project__c).Id,
                Project_Configuration__c = config.Id
            ));
        }
        Database.insert(folders, AccessLevel.SYSTEM_MODE);

        for (Document__c parent : newParents) {
            plan.documentIds.add(parent.Id);
        }
        for (Document__c folder : folders) {
            plan.documentIds.add(folder.Id);
        }
        return plan;
    }

    // Folders of these configurations that SharePoint never created, with a parent that failed the same way listed
    // before the folders inside it. A folder whose parent is still being created is left for that job.
    @TestVisible
    private static List<Id> stalledFolders(Set<Id> configurationIds) {
        List<Id> documentIds = new List<Id>();
        Set<Id> queued = new Set<Id>();
        Datetime stalledBefore = System.now().addSeconds(-STALLED_AFTER_SECONDS);
        for (Document__c folder : [
            SELECT Id, Parent_Document__c, Parent_Document__r.Document_Id__c, Parent_Document__r.CreatedDate
            FROM Document__c
            WHERE Project_Configuration__c IN :configurationIds AND Document_Id__c = null AND CreatedDate < :stalledBefore
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            if (folder.Parent_Document__c == null) {
                continue;
            }
            Boolean parentReady = String.isNotBlank(folder.Parent_Document__r.Document_Id__c);
            Boolean parentStalled = !parentReady && folder.Parent_Document__r.CreatedDate < stalledBefore;
            if (parentStalled && queued.add(folder.Parent_Document__c)) {
                documentIds.add(folder.Parent_Document__c);
            }
            if ((parentReady || parentStalled) && queued.add(folder.Id)) {
                documentIds.add(folder.Id);
            }
        }
        return documentIds;
    }

    private static Boolean folderJobPending() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'CreateSharePointFoldersQueueable' AND Status IN :PENDING_JOB_STATUSES
            WITH SYSTEM_MODE
        ] > 0;
    }

    private static void enqueue(List<Id> documentIds, Boolean waitForParent) {
        // Enqueueing past the limit throws an uncatchable LimitException that would roll back the save
        if (documentIds.isEmpty() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        CreateSharePointFoldersQueueable job = new CreateSharePointFoldersQueueable(documentIds);
        if (waitForParent) {
            // Gives the job that is creating the parent folder a minute to finish first
            System.enqueueJob(job, 1);
        } else {
            System.enqueueJob(job);
        }
        lastQueued = documentIds;
    }

    // "PC-0001 - Vauxhall Dstrct - 2 BR" without the characters SharePoint does not accept in names. The number and
    // the unit type are always kept whole; a long project name is shortened to fit.
    public static String folderName(Project_Configuration__c config) {
        String configNumber = clean(config.Name);
        String unitType = String.isBlank(config.Unit_Type__c) ? '' : clean(config.Unit_Type__c);
        String projectName = config.Project__r == null || String.isBlank(config.Project__r.Name) ? '' : clean(config.Project__r.Name);
        Integer room = MAX_NAME - configNumber.length() - 3 - (unitType == '' ? 0 : unitType.length() + 3);
        projectName = projectName.left(Math.max(room, 0)).trim();

        List<String> parts = new List<String>{ configNumber };
        if (projectName != '') {
            parts.add(projectName);
        }
        if (unitType != '') {
            parts.add(unitType);
        }
        // SharePoint refuses names that end in a dot or a space
        return String.join(parts, ' - ').left(MAX_NAME).replaceAll('[.\\s]+$', '');
    }

    private static String clean(String value) {
        return value.replaceAll('[\\\\/:*?"<>|#%]', '_').normalizeSpace();
    }
}