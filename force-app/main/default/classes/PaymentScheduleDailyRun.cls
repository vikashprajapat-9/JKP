public class PaymentScheduleDailyRun implements DataBase.Batchable<sobject> {
    
    public Database.QueryLocator Start(DataBase.BatchableContext bc){
     
    return DataBase.getQueryLocator('SELECT Id,Demand_Letter_Sent__c, Total_Due_Amount__c, Demand_Letter_Sent_Date__c,Opportunity__r.Project__r.Payment_Made_In_Days__c FROM Payment_Schedule__c WHERE Demand_Letter_Sent__c =true AND Total_Due_Amount__c >=0'); 
    }
    public void execute (DataBase.BatchableContext bc,List<Payment_Schedule__c>scope){
     
            for(Payment_Schedule__c p:scope){
                Integer daysAllowed = Integer.valueOf (p.Opportunity__r.Project__r.Payment_Made_In_Days__c) ; // 15 Allowed Days
                           
                Integer dayspassed = Date.valueOf (p.Demand_Letter_Sent_Date__c).daysBetween(Date.Today());  //  Demand_Letter_Sent_Date__c - Date.today(); ==> No of days (20)
                
            if(dayspassed > daysAllowed){
            system.debug('====== Days Allowed ===>            '+daysAllowed); //20
            system.debug('====== dayspassed till Today() ====>'+dayspassed); // 10.
            Case_DeedOfCancellation.getPaymentSchedule(p.Id);
            system.debug('====== Excute method executed ======'+p);  
                }
             
         
        }
    }
    Public void finish (DataBase.BatchableContext bc){
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] {'nazirsfdc@gmail.com'});
        mail.setSubject('Payment due');
        mail.setPlainTextBody('This customer payment is due');
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
         system.debug('======Send Email======'+mail);
    }
}