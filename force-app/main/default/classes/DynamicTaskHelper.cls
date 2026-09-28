public with sharing class DynamicTaskHelper {
    @AuraEnabled
    Public Static Task getCurrentTaskRecord(String recordId){
        System.debug('recordId==>'+recordId);
        Task TaskRec = new Task();
        try{
            if(!String.isBlank(recordId)){
                TaskRec = [
                            SELECT Id, Subject, Description, Status, WhoId, WhatId, ActivityDate, Task_Master__c, 
                            Task_Master__r.Name, Task_Master__r.Object_Type__c, Task_Master__r.Task_Subject__c, 
                            Task_Master__r.Action_Type__c, Task_Master__r.Action_URL__c, Task_Master__r.IsActive__c 
                            FROM Task 
                            WHERE Id=:recordId 
                            AND Task_Master__r.IsActive__c = true];
                system.debug('TaskRec ====> '+TaskRec);
                if(TaskRec !=null){
                    System.debug('TaskRec==>'+TaskRec);
                    return TaskRec;
                }
            }
            else {
                System.debug('recordId is null');
            }
        }catch (QueryException e) {
            throw new AuraHandledException(
                'Unable to find an active Task Master for this Task.'
            );
        }catch(Exception e){
            System.debug('The Error ::'+e.getMessage() +' AND Error Line No :'+e.getLineNumber());
        }
        return null;
    }
}