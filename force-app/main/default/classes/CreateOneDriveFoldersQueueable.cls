public class CreateOneDriveFoldersQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> docIds;

    // Set only while execute() is running. DocumentCreationHandler checks it and adds the documents it
    // just created to deferredDocIds instead of enqueueing a job of its own, so this class can chain
    // exactly one follow-up job carrying both the remaining records and those new documents.
    public static Boolean deferChildJobs = false;
    public static List<Id> deferredDocIds = new List<Id>();

    public CreateOneDriveFoldersQueueable(List<Id> docIds) {
        this.docIds = docIds;
    }

    public void execute(QueueableContext context) {
        if(!docIds.isEmpty()){
            Id currentDocId = docIds.remove(0);

            // Only ONE job may be enqueued from inside a running queueable. processData creates the folder
            // and then calls DocumentCreationHandler, which used to enqueue its own job - that job plus the
            // chain below was the second one, and threw "Too many queueable jobs added to the queue: 2".
            // DocumentCreationHandler now hands its new document ids back through deferredDocIds instead.
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
                System.enqueueJob(new CreateOneDriveFoldersQueueable(remaining));
            }
        }
    }

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
                Document__c docMain = new Document__c();
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
                System.debug('objectType ===> ' + objectType);
                if (String.isBlank(folderName)) {
                    System.debug('Skipping folder creation: folderName is null');
                    return;
                }
                OneDriveService svc = new OneDriveService();
                String token = svc.getAccessToken();
                System.debug('token==>'+token);

                HttpRequest req = new HttpRequest();
                req.setMethod('POST');
                String endpointUrl;
                String userId = 'isha.raj@utilitarianlabs.com'; //'vamsi.krishna@utilitarianlabs.com';
                if (String.isBlank(parentfolderId)) {
                    endpointUrl = 'https://graph.microsoft.com/v1.0/users/' + userId + '/drive/root/children';
                } else {
                    // Parent folderId provided - create inside it
                    endpointUrl = 'https://graph.microsoft.com/v1.0/users/' + userId + '/drive/items/' + parentfolderId + '/children';
                }

                req.setEndpoint(endpointUrl);
                req.setHeader('Authorization', 'Bearer ' + token);
                req.setHeader('Content-Type', 'application/json');

                String body = JSON.serialize(new Map<String, Object>{
                    'name' => folderName,
                    'folder' => new Map<String, Object>(),
                    '@microsoft.graph.conflictBehavior' => 'rename'
                });

                req.setBody(body);
                req.setTimeout(60000);

                Http http = new Http();
                HttpResponse res = new HttpResponse();
                if (!Test.isRunningTest()) {
                    res = http.send(req);
                }

                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    System.debug('responseBody==>'+responseBody);
                    String folderId = String.valueOf(responseBody.get('id'));
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
            }
        } catch(Exception e) {
            System.debug('Error creating folder for category ' + e.getMessage() + ' at Line Number ===> ' + e.getLineNumber() + ' at Class Name ===> ' + e.getStackTraceString());
        }
    }
}