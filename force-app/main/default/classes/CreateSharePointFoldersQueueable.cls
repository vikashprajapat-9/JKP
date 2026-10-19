public class CreateSharePointFoldersQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> docIds;

    // Set only while execute() is running. DocumentCreationHandler checks it and adds the documents it
    // just created to deferredDocIds instead of enqueueing a job of its own, so this class can chain
    // exactly one follow-up job carrying both the remaining records and those new documents.
    public static Boolean deferChildJobs = false;
    public static List<Id> deferredDocIds = new List<Id>();

    public CreateSharePointFoldersQueueable(List<Id> docIds) {
        this.docIds = docIds;
    }

    public void execute(QueueableContext context) {
        if(!docIds.isEmpty()){
            Id currentDocId = docIds.remove(0);

            // Only ONE job may be enqueued from inside a running queueable. processData creates the folder
            // and then calls DocumentCreationHandler, which would otherwise enqueue its own job next to the
            // chain below ("Too many queueable jobs added to the queue: 2"), so DocumentCreationHandler hands
            // its new document ids back through deferredDocIds instead.
            deferChildJobs = true;
            deferredDocIds = new List<Id>();
            try {
                processData(currentDocId);
            } finally {
                deferChildJobs = false;
            }

            List<Id> remaining = new List<Id>(docIds);
            remaining.addAll(deferredDocIds);
            deferredDocIds = new List<Id>();

            if(!remaining.isEmpty() && !Test.isRunningTest()){
                System.enqueueJob(new CreateSharePointFoldersQueueable(remaining));
            }
        }
    }

    // Creates the record's folder in the SharePoint library: an account or project folder at the top, an opportunity
    // folder inside its account's folder and a Document's folder inside its parent's folder. The folder id is saved
    // on the record and DocumentCreationHandler then adds the record's own Documents.
    public static void processData(Id docId){
        try {
            System.debug('docId ===> ' + docId);
            if (docId != null) {
                String folderName;
                String parentFolderId;
                List<Document__c> docRec;
                List<Account> accountRec;
                List<Project__c> projectRec;
                List<Opportunity> oppRec;
                String objectType = docId.getSObjectType().getDescribe().getName();
                System.debug('objectType ===> ' + objectType);
                if(objectType == 'Account') {
                    accountRec = [SELECT Id, Name, RecordTypeId FROM Account WHERE Id = :docId WITH SYSTEM_MODE];
                    folderName = accountRec[0].Name;
                }
                else if(objectType == 'Project__c') {
                    projectRec = [SELECT Id, Name FROM Project__c WHERE Id = :docId WITH SYSTEM_MODE LIMIT 1];
                    folderName = projectRec[0].Name;
                }else if(objectType == 'Opportunity') {
                    oppRec = [SELECT Id, Name, AccountId, Account.Document_Id__c FROM Opportunity WHERE Id = :docId WITH SYSTEM_MODE LIMIT 1];
                    parentFolderId = (oppRec[0].AccountId != null && oppRec[0].Account.Document_Id__c != null) ? oppRec[0].Account.Document_Id__c : null;
                    folderName = parentFolderId != null ? oppRec[0].Name : null;
                }
                else if(objectType == 'Document__c') {
                    docRec = [SELECT Id, Name, Document_Id__c, Account__c, Account__r.Document_Id__c, Opportunity__c, Opportunity__r.Document_Id__c, Project__c, Project__r.Document_Id__c, Parent_Document__c, Parent_Document__r.Document_Id__c
                                FROM Document__c WHERE Id = :docId WITH SYSTEM_MODE LIMIT 1];
                    if (!docRec.isEmpty()) {
                        parentFolderId =
                            (docRec[0].Parent_Document__c != null && docRec[0].Parent_Document__r.Document_Id__c != null) ? docRec[0].Parent_Document__r.Document_Id__c :

                            (docRec[0].Project__c != null && docRec[0].Project__r.Document_Id__c != null) ? docRec[0].Project__r.Document_Id__c :
                            (docRec[0].Opportunity__c != null && docRec[0].Opportunity__r.Document_Id__c != null) ? docRec[0].Opportunity__r.Document_Id__c :
                            (docRec[0].Account__c != null && docRec[0].Account__r.Document_Id__c != null) ? docRec[0].Account__r.Document_Id__c :
                            null;
                        folderName = parentFolderId != null ? docRec[0].Name : null;
                    }
                }
                System.debug('folderName ===> ' + folderName);
                System.debug('parentFolderId ===> ' + parentFolderId);
                if (String.isBlank(folderName)) {
                    System.debug('Skipping folder creation: folderName is null');
                    return;
                }

                // SharePoint refuses names with \\ / : * ? " < > | # % (for example "M/s Perera Holdings"), so createFolder
                // cleans the name first; a blank parent means the top of the library. A refused folder throws, is logged
                // below and leaves the record unchanged.
                String folderId = SharePointDocumentManagerController.createFolder(parentFolderId, folderName);
                System.debug('Created folder ID: ' + folderId);
                if (objectType == 'Account') {
                    accountRec[0].Document_Id__c = folderId;
                    Database.update(accountRec, AccessLevel.SYSTEM_MODE);
                    DocumentCreationHandler dch = new DocumentCreationHandler();
                    dch.CreateDocuments(accountRec);
                }
                else if (objectType == 'Project__c') {
                    projectRec[0].Document_Id__c = folderId;
                    Database.update(projectRec, AccessLevel.SYSTEM_MODE);
                    DocumentCreationHandler dch = new DocumentCreationHandler();
                    dch.CreateDocuments(projectRec);
                }
                else if (objectType == 'Opportunity') {
                    oppRec[0].Document_Id__c = folderId;
                    Database.update(oppRec, AccessLevel.SYSTEM_MODE);
                    DocumentCreationHandler dch = new DocumentCreationHandler();
                    dch.CreateDocuments(oppRec);
                }
                else if (objectType == 'Document__c') {
                    docRec[0].Document_Id__c = folderId;
                    Database.update(docRec, AccessLevel.SYSTEM_MODE);
                    DocumentCreationHandler dch = new DocumentCreationHandler();
                    dch.CreateDocuments(docRec);
                }
            }
        } catch(Exception e) {
            // The message names the HTTP status and Graph's error code only
            System.debug(LoggingLevel.ERROR, 'SharePoint did not create the folder for ' + docId + ': ' + e.getMessage()
                + ' at Line Number ===> ' + e.getLineNumber() + ' at Class Name ===> ' + e.getStackTraceString());
        }
    }
}