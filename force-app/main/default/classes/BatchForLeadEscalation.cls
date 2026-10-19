global  class BatchForLeadEscalation implements Database.Batchable<SObject>{
    global Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator([SELECT Id,OwnerId,Lead_Classification__c, Lead_Assigned_Date_Time__c FROM Lead WHERE  Lead_Assigned_Date_Time__c != null AND Status NOT IN ('In-Discussion','Not Reachable','Not Interested','Contacted' ) AND Lead_Classification__c IN ('Hot','Warm')]); //Lead_Follow_Up_DateTime__c != null AND
    }
    global void execute(Database.BatchableContext BC, List<Lead> scope){
        system.debug('Lead Escalation Batch Started');
        system.debug('scope size: '+scope.size());
        system.debug('scope: '+scope);
        List<Lead> leadsToUpdate = new List<Lead>();
        for(Lead l:scope){
            Integer mins  =Integer.valueOf(System.now().getTime() - l.Lead_Assigned_Date_Time__c.getTime())/60000;
            if(l.Lead_Classification__c == 'Hot' && mins >= 60){
                LeadEscalationHelper.sendHotLeadEscalation(l.Id);
                system.debug(' Hot Lead Escalation  for Lead Id: '+l.Id);
                
            }
            else if(l.Lead_Classification__c == 'Warm' && mins >= 240){
                LeadEscalationHelper.sendWarmLeadEscalation(l.Id);
                system.debug('Warm Lead Escalation for Lead Id: '+l.Id);
            }
            
        }
    }
    global void finish(Database.BatchableContext BC){
        System.debug('Lead Escalation Batch Finished');
    }
}