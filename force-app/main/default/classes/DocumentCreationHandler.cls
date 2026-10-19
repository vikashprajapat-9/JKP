// Creates the Document records of new accounts, projects and opportunities. Without sharing because the SharePoint job
// that calls it runs as whoever created the record, which can be a portal partner adding an executive: partners have
// no sharing access to Document categories or to the new account, and the Documents would silently not be created.
public without sharing class DocumentCreationHandler {

    // Record types (lower case) whose records get Documents: those a Document Master with categories names in its
    // Record Type, for example "Channel partner" for Channel Partner accounts
    public static Set<String> recordTypesWithDocuments() {
        Set<String> names = new Set<String>();
        for (Document_Category__c category : new Categories().withRecordType()) {
            names.add(category.Document_Master__r.Record_Type__c.toLowerCase());
        }
        return names;
    }

    // The categories, by name, of the Document Master for this record type (in any capitalisation)
    public static List<Document_Category__c> categoriesForRecordType(String recordTypeName) {
        List<Document_Category__c> categories = new List<Document_Category__c>();
        if (String.isBlank(recordTypeName)) {
            return categories;
        }
        for (Document_Category__c category : new Categories().withRecordType()) {
            if (category.Document_Master__r.Record_Type__c.equalsIgnoreCase(recordTypeName.trim())) {
                categories.add(category);
            }
        }
        return categories;
    }

    // Reads every category whoever runs it: the Partner Portal's guest user registers channel partners but has no
    // sharing access to Document categories
    private without sharing class Categories {
        List<Document_Category__c> withRecordType() {
            return [
                SELECT Id, Name, Document_Master__r.Record_Type__c
                FROM Document_Category__c
                WHERE Document_Master__r.Record_Type__c != null
                WITH SYSTEM_MODE
                ORDER BY Name
            ];
        }
    }

    public void CreateDocuments(List<SObject> sObjectList){
        try {
            System.debug('sObjectList==>'+sObjectList); 
            List<Document__c> documentsToInsert = new List<Document__c>();
            List<String> docIds = new List<String>();
            Map<String,List<Document_Category__c>> getAllData = new Map<String,List<Document_Category__c>>();
            // Categories left without a master (it was deleted) are skipped
            List<Document_Category__c> getAllDocumentCategorys  = [SELECT Id, Name, Document_Master__r.Name, Document_Master__c, Document_Master__r.Record_Type__c FROM Document_Category__c WHERE Document_Master__c != null WITH SYSTEM_MODE ORDER BY Name];
            for(Document_Category__c docCat : getAllDocumentCategorys){
                // Keyed by the master's Record Type when it has one, otherwise by its Name - in lower case, because the
                // Record Type picklist ("Channel partner") need not match the record type's own name ("Channel Partner")
                String key = (docCat.Document_Master__r.Record_Type__c != null
                    ? docCat.Document_Master__r.Record_Type__c
                    : docCat.Document_Master__r.Name).toLowerCase();
                if(!getAllData.containsKey(key)) {
                    getAllData.put(key, new List<Document_Category__c>());
                }
                getAllData.get(key).add(docCat);
            }
            System.debug('getAllData==>'+getAllData);
            
            for (SObject record : sObjectList){
                String recordName = record.getSObjectType().getDescribe().getLabel(); 
                System.debug('recordName==>'+recordName);
                // Accounts take their categories from a master that names their record type (the branch below); a master
                // named "Account" without a Record Type is not used for them
                if (recordName != 'Account' && getAllData.containsKey(recordName.toLowerCase())){
                    System.debug('Inside if condition in DocumentCreationHandler');
                    List<Document_Category__c> relatedCategories = getAllData.get(recordName.toLowerCase());
                    for (Document_Category__c category : relatedCategories) {
                        Document__c newDoc = new Document__c();
                        newDoc.Name = category.Name;
                        if(recordName == 'Project'){
                            newDoc.Project__c = record.Id;
                        }
                        else if(recordName == 'Opportunity'){
                            // JKP Opportunity has no record types, so its documents come from a Document Master named "Opportunity"
                            newDoc.Opportunity__c = record.Id;
                        }
                        // else if(recordName == 'Unit'){
                        //     newDoc.Unit__c = record.Id;   
                        // }
                        // else if(recordName == 'Project'){
                        //     newDoc.Project__c = record.Id;
                        // }
                        documentsToInsert.add(newDoc);
                    }
                }
                else if(recordName == 'Account'){
                    Account acc = (Account) record;
                    Account acc1 = [SELECT Id,Name, RecordTypeId FROM Account WHERE Id = :acc.Id WITH SYSTEM_MODE LIMIT 1];
                    String recordType = Schema.SObjectType.Account.getRecordTypeInfosById().get(acc1.RecordTypeId).getName().toLowerCase();
                    System.debug('recordType==>'+recordType);
                    if (getAllData.containsKey(recordType)){
                        List<Document_Category__c> relatedCategories = getAllData.get(recordType);
                        for (Document_Category__c category : relatedCategories) {
                            Document__c newDoc = new Document__c();
                            newDoc.Name = category.Name;
                            newDoc.Account__c = record.Id;  
                            documentsToInsert.add(newDoc);
                        }
                    }
                }
                else if(recordName == 'Project') {
                    Project__c proj = (Project__c) record;
                    Project__c proj1 = [SELECT Id,Name FROM Project__c WHERE Id = :proj.Id WITH SYSTEM_MODE LIMIT 1];
                    Document__c newDoc = new Document__c();
                    newDoc.Name = proj1.Name;
                    newDoc.Project__c = record.Id;  
                    documentsToInsert.add(newDoc);
                     // ---- ADDED: also create documents from Document Category records for Project ----
                    if (getAllData.containsKey('project')) {
                        List<Document_Category__c> relatedCategories = getAllData.get('project');
                        for (Document_Category__c category : relatedCategories) {
                            Document__c catDoc = new Document__c();
                            catDoc.Name = category.Name;
                            catDoc.Project__c = record.Id;
                            documentsToInsert.add(catDoc);
                        }
                    }
                    // ---- END ADDED ----
                }
                // else if(recordName == 'Document'){
                //     Document__c doc = (Document__c) record;
                //     Document__c docRec = [SELECT Id,Name,Account__c,Account__r.Name, Account__r.RecordTypeId FROM Document__c WHERE Id = :doc.Id LIMIT 1];
                //     String recordType = Schema.SObjectType.Account.getRecordTypeInfosById().get(docRec.Account__r.RecordTypeId).getName();
                //     System.debug('recordType==>'+recordType);
                //     if (getAllData.containsKey(recordType)){
                //         List<Document_Category__c> relatedCategories = getAllData.get(recordType);
                //         for (Document_Category__c category : relatedCategories) {
                //             if(recordType == 'Customer'){
                //                 Document__c newDoc = new Document__c();
                //                 newDoc.Name = category.Name;
                //                 newDoc.Parent_Document__c = record.Id;
                //                 documentsToInsert.add(newDoc);
                //             }
                //         }
                //     }
                // }               
                System.debug('documentsToInsert==>'+documentsToInsert);
            }
            Database.insert(documentsToInsert, AccessLevel.SYSTEM_MODE);
            for(Document__c doc : documentsToInsert){
                docIds.add(doc.Id);
            }
            
            if(docIds.size() > 0){
                if(CreateSharePointFoldersQueueable.deferChildJobs){
                    // Running inside CreateSharePointFoldersQueueable.execute, where only one job may be
                    // enqueued - hand the ids back so they join that job's chain instead.
                    for(String newDocId : docIds){
                        CreateSharePointFoldersQueueable.deferredDocIds.add(Id.valueOf(newDocId));
                    }
                } else {
                    System.enqueueJob(new CreateSharePointFoldersQueueable(docIds));
                }
            }
            
        } catch (Exception e) {
            System.debug('Error in Creating Documents: ' + e.getMessage() + ' at line: ' + e.getLineNumber());
        } 
    }
}