public with sharing class DocumentCreationHandler {
    public void CreateDocuments(List<SObject> sObjectList){
        try {
            System.debug('sObjectList==>'+sObjectList); 
            List<Document__c> documentsToInsert = new List<Document__c>();
            List<String> docIds = new List<String>();
            Map<String,List<Document_Category__c>> getAllData = new Map<String,List<Document_Category__c>>();
            List<Document_Category__c> getAllDocumentCategorys  = [SELECT Id, Name, Document_Master__r.Name, Document_Master__c, Document_Master__r.Record_Type__c FROM Document_Category__c WITH SYSTEM_MODE ORDER BY Name];
            for(Document_Category__c docCat : getAllDocumentCategorys){
                String docMasterName = docCat.Document_Master__r.Name;
                String docMasterRecordType = docCat.Document_Master__r.Record_Type__c;
                if(docMasterRecordType != null && !getAllData.containsKey(docMasterRecordType)) {
                    getAllData.put(docMasterRecordType, new List<Document_Category__c>());
                }
                else if(docMasterRecordType == null && !getAllData.containsKey(docMasterName)) {
                    getAllData.put(docMasterName, new List<Document_Category__c>());
                }
                if(docMasterRecordType != null && getAllData.get(docMasterRecordType) != null) {
                    getAllData.get(docMasterRecordType).add(docCat);
                }
                else if(docMasterRecordType == null && getAllData.get(docMasterName) != null){
                    getAllData.get(docMasterName).add(docCat);
                }
            }
            System.debug('getAllData==>'+getAllData);
            
            for (SObject record : sObjectList){
                String recordName = record.getSObjectType().getDescribe().getLabel(); 
                System.debug('recordName==>'+recordName);
                if (getAllData.containsKey(recordName)){
                    System.debug('Inside if condition in DocumentCreationHandler');
                    List<Document_Category__c> relatedCategories = getAllData.get(recordName);          
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
                    String recordType = Schema.SObjectType.Account.getRecordTypeInfosById().get(acc1.RecordTypeId).getName();
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
                    if (getAllData.containsKey('Project')) {
                        List<Document_Category__c> relatedCategories = getAllData.get('Project');
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
                if(CreateOneDriveFoldersQueueable.deferChildJobs){
                    // Running inside CreateOneDriveFoldersQueueable.execute, where only one job may be
                    // enqueued - hand the ids back so they join that job's chain instead.
                    for(String newDocId : docIds){
                        CreateOneDriveFoldersQueueable.deferredDocIds.add(Id.valueOf(newDocId));
                    }
                } else {
                    System.enqueueJob(new CreateOneDriveFoldersQueueable(docIds));
                }
            }
            
        } catch (Exception e) {
            System.debug('Error in Creating Documents: ' + e.getMessage() + ' at line: ' + e.getLineNumber());
        } 
    }
}