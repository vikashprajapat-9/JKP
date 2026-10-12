public class Case_DeedOfCancellation {
    public static void getPaymentSchedule(String Id){
        system.debug('====== Case_DeedOfCancellation ======'+Id);
        List<Payment_Schedule__c> p=
            [
             SELECT Id,
             Opportunity__r.Id,
             Opportunity__r.AccountId 
             FROM 
             Payment_Schedule__c 
             where Id=:Id
            ];
        
        system.debug('======Payment_Schedule__c QUERY  ======'+Id);
        
        List<Case> cases=new List<Case>();
        //Map<String,Id> mapIdToCase=new Map<String,Id>();
        List<Task> taskList=new List<Task>();
        
        for(Payment_Schedule__c ps:p){
            
            
            Case c=new Case();
            c.Name__c='Payment due for customer';
            c.Subject='Payment due for customer';
            c.AccountId = ps.Opportunity__r.AccountId;
            c.Opportunity__c=ps.Opportunity__c;
            insert c; 
            
            Task t=new Task();
            t.Subject='payment schedule';
            t.Priority='High';
            t.Description='Payment mission';
            t.ActivityDate=Date.Today().adddays(3);
            t.WhatId= c.Id;
            taskList.add(t); 
            
            
            
        }
        
        
        if(!taskList.isEmpty()){
            insert taskList;
            system.debug('===== Task created ===='+taskList);
        }
        
        
    }
}