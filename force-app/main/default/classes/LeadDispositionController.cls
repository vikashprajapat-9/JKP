public with sharing class LeadDispositionController {

    @AuraEnabled(cacheable=true)
    public static List<Call_Disposition__c> getDispositions(Id leadId) {

        return [
            SELECT Id,Name,Follow_Up_DateTime__c,Direction__c,Call_DateTime__c, Subject__c,Description__c,
                    Call_Disposition__c, CreatedDate,Owner.Name FROM Call_Disposition__c WHERE Lead__c = :leadId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static Call_Disposition__c saveDisposition(
        Id leadId,
        String subject,
        String description,
        String disposition,
        DateTime callDateTime,
        DateTime followUpDateTime,
        String lossReason,
        String otherLossReason,
        String purchasePurpose,
        String unitType,
        Integer unitSize,
        String purchaseTimeline,
        String assessBudget,
        String assessFinanceReadiness
    ) {

        Call_Disposition__c cd = new Call_Disposition__c();
        cd.Lead__c = leadId;
        cd.Subject__c = subject;
        cd.Description__c = description;
        cd.Call_Disposition__c = disposition;
        cd.Call_DateTime__c = callDateTime;
        cd.Follow_Up_DateTime__c = followUpDateTime;
        system.debug('LeadDispositionController.saveDisposition: ' + cd);

        insert cd;

        
        // Lead lead = [ SELECT Id, Status,OwnerId,Lead_Follow_Up_DateTime__c,Follow_Up_count__c,Lead_Assigned_Date_Time__c FROM Lead WHERE Id = :leadId ];

        //     Integer count = lead.Follow_Up_Count__c == null? 0 : Integer.valueOf(lead.Follow_Up_Count__c);
        //     //Integer days = lead.Lead_Assigned_Date_Time__c.date().daysBetween(Date.today());
        //     Integer days = 0;
        //         if (lead.Lead_Assigned_Date_Time__c != null && callDateTime != null) {
        //             days = lead.Lead_Assigned_Date_Time__c.date().daysBetween(callDateTime.date());
        //         }
        //         Datetime nextFollowUp;
        //         Task taskToInsert;
        //         if (disposition == 'In Discussion') {
        //             count++;
        //             lead.Follow_Up_Count__c = count;
        //             lead.Status = 'In-Discussion';
        //             lead.Lead_Follow_Up_DateTime__c = followUpDateTime;
        //             taskToInsert = new Task();
        //             taskToInsert.Subject = 'Lead Follow Up Call';
        //             taskToInsert.Status = 'Not Started';
        //             taskToInsert.Priority = 'Normal';
        //             taskToInsert.OwnerId = lead.OwnerId;
        //             taskToInsert.WhoId = lead.Id;
        //             taskToInsert.ActivityDate = followUpDateTime.date();
        //             taskToInsert.Description = 'Follow-up generated from Call Disposition.';

        //         }
        //         // else if (disposition == 'Not Reachable') {
                //     lead.Status = 'Not Reachable';
                //     if(days <= 7){
                //         // Week  1
                //         if(count >= 2){
                //             //return cd; 
            
                //         }
                //         count++;
                //         if (lead.Lead_Follow_Up_DateTime__c != null) {
                //             nextFollowUp = lead.Lead_Follow_Up_DateTime__c.addDays(1);
                //         } else {
                //             nextFollowUp = System.now().addDays(1); 
                //         }
                //         System.debug('Count=' + count);
                //         System.debug('Days=' + days);
                //     }
                //     else if(days <= 21){
                //         // Week 2-3
                //         if(count >= 3){
                //             return cd;
                //         }
                //         count++;
                //         nextFollowUp =lead.Lead_Follow_Up_DateTime__c.addDays(1);
                //         System.debug('Count=' + count);
                //         System.debug('Days=' + days);
                //     }
                //     else if(days >= 28 && days <= 42){
                //         // Week 5-6
                //         if(count >= 4){
                //             Group marketingQueue = [ SELECT Id FROM Group  WHERE Type='Queue' AND DeveloperName='Marketing_Queue' LIMIT 1 ];
                //             lead.OwnerId = marketingQueue.Id;
                //             update lead;
                //         return cd;
                //         }
                //         count++;
                //         nextFollowUp = lead.Lead_Follow_Up_DateTime__c.addDays(1);
                //         System.debug('Count=' + count);
                //         System.debug('Days=' + days);
                //     }
                //     else{
                //         // No more automatic follow-ups
                //         Group marketingQueue = [ SELECT Id FROM Group  WHERE Type='Queue' AND DeveloperName='Marketing_Queue' LIMIT 1 ];
                //         lead.OwnerId = marketingQueue.Id;
                //         update lead;
                //         return cd;
                //     }
                //     lead.Follow_Up_Count__c = count;
                //     lead.Lead_Follow_Up_DateTime__c = nextFollowUp;
                //     taskToInsert = new Task();
                //     taskToInsert.Subject = 'Lead Follow Up Call';
                //     taskToInsert.Status = 'Not Started';
                //     taskToInsert.Priority = 'Normal';
                //     taskToInsert.OwnerId = lead.OwnerId;
                //     taskToInsert.WhoId = lead.Id;
                //     taskToInsert.ActivityDate = nextFollowUp.date();
                //     taskToInsert.Description = 'Follow-up generated from Call Disposition.';
                // }

        Lead lead = [ SELECT Id, Status,OwnerId,Lead_Follow_Up_DateTime__c,Follow_Up_count__c,Lead_Assigned_Date_Time__c FROM Lead WHERE Id = :leadId ];

            Integer count = lead.Follow_Up_Count__c == null? 0 : Integer.valueOf(lead.Follow_Up_Count__c);
            Integer diff = 0;

                if (lead.Lead_Assigned_Date_Time__c != null &&
                    lead.Lead_Follow_Up_DateTime__c != null) {

                    diff = lead.Lead_Assigned_Date_Time__c.date()
                        .daysBetween(lead.Lead_Follow_Up_DateTime__c.date());
                }
                Task taskToInsert;
                if (disposition == 'In Discussion') {
                    count++;
                    lead.Follow_Up_Count__c = count;
                    lead.Status = 'In-Discussion';
                    lead.Lead_Follow_Up_DateTime__c = followUpDateTime;
                    taskToInsert = new Task();
                    taskToInsert.Subject = 'Lead Follow Up Call';
                    taskToInsert.Status = 'Not Started';
                    taskToInsert.Priority = 'Normal';
                    taskToInsert.OwnerId = lead.OwnerId;
                    taskToInsert.WhoId = lead.Id;
                    taskToInsert.ActivityDate = followUpDateTime.date();
                    taskToInsert.Description = 'Follow-up generated from Call Disposition.';

                }
                else if (disposition == 'Not Reachable') {
                    if (count >= 4) {
                        lead.Status = 'Not Reachable';
                        Group marketingQueue = [SELECT Id  FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Marketing_Queue' LIMIT 1];
                        lead.OwnerId = marketingQueue.Id;
                    }
                    else {
                        count++;
                        lead.Follow_Up_Count__c = count;
                        lead.Status = 'Not Reachable';
                        Datetime nextFollowUp;
                        if (count == 1) {

                            // First call itself is Not Reachable
                            nextFollowUp = System.now().addDays(1);

                        }
                        else if (count == 2) {

                            // If the lead already had a discussion follow-up (7+ days from assignment),
                            // then first Not Reachable should be next day.
                            if (diff >= 7) {
                                nextFollowUp = lead.Lead_Follow_Up_DateTime__c.addDays(1);
                            }
                            else {
                                // Pure Not Reachable journey
                                nextFollowUp = lead.Lead_Follow_Up_DateTime__c.addDays(1);
                            }

                        }
                        else if (count == 3) {

                            if (diff >= 8 && diff < 21) {
                                Date week5 = lead.Lead_Follow_Up_DateTime__c.date().addDays(1);

                                nextFollowUp = Datetime.newInstance( week5, lead.Lead_Follow_Up_DateTime__c.time() );
                            }
                            else {
                                // Pure Not Reachable flow
                                nextFollowUp = lead.Lead_Assigned_Date_Time__c.addDays(7);
                            }

                        }
                        else { // count == 4
                            if (diff >= 21) {
                                // Already in Week 5
                                nextFollowUp = lead.Lead_Follow_Up_DateTime__c.addDays(1);
                            }
                            else {
                                nextFollowUp = lead.Lead_Assigned_Date_Time__c.addDays(28);
                            }
                        }      
                        lead.Lead_Follow_Up_DateTime__c = nextFollowUp;

                        taskToInsert = new Task();
                        taskToInsert.Subject = 'Lead Follow Up Call';
                        taskToInsert.Status = 'Not Started';
                        taskToInsert.Priority = 'Normal';
                        taskToInsert.OwnerId = lead.OwnerId;
                        taskToInsert.WhoId = lead.Id;
                        taskToInsert.ActivityDate = nextFollowUp.date();
                        taskToInsert.Description = 'Follow-up generated from Call Disposition.';
                    }
                }

                if (taskToInsert != null) {
                    insert taskToInsert;

            }


            if(disposition == 'Good Response') {
                lead.Status = 'Contacted';
                lead.Purchase_Purpose__c = purchasePurpose;
                lead.Unit_Type__c = unitType;
                lead.Unit_Size__c = unitSize;
                lead.Purchase_Timeline__c = purchaseTimeline;
                lead.Assess_Budget__c = assessBudget;
                lead.Assess_Finance_Readiness__c = assessFinanceReadiness;
            }
            if(disposition == 'Not Interested') {
                lead.Status = 'Not Interested';
                Group distributionQueue = [SELECT Id  FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Re_Distributin_Queue' LIMIT 1];
                        lead.OwnerId = distributionQueue.Id;
            }
            if (lead.Status != null) {
                update lead;
            }
        return cd;
    }
}