public without sharing class FinaliseCostSheetController {
    
    public class CostSheetWrapper {
        @AuraEnabled public List<Cost_Sheet__c> costSheetRecords { get; set; }
        @AuraEnabled public List<Payment_Schedule__c> paymentScheduleRecords { get; set; }
        @AuraEnabled public List<Pricing_Element__c> costPricingAsstnList { get; set; }
        
        public CostSheetWrapper() {
            costSheetRecords = new List<Cost_Sheet__c>();
            paymentScheduleRecords = new List<Payment_Schedule__c>();
            costPricingAsstnList = new List<Pricing_Element__c>();
        }
    }
    
    @AuraEnabled
    public static CostSheetWrapper getRecordDetails(Id recordId) {
        System.debug('Received Record Id: ' + recordId);
        // Query the Task record
       // Task ts = [SELECT Id, WhatId FROM Task WHERE Id = :recordId LIMIT 1];
        Opportunity oppRec = [SELECT Id,Cost_Sheet_Template__c from Opportunity where Id =:recordId  LIMIT 1]; //ts.WhatId
       // System.debug('Task: ' + ts);
        System.debug('Opportunity: ' + oppRec);

        
        List<Cost_Sheet__c> relatedCostSheetRecords = [SELECT Id, Opportunity__c, Name, Cost_Scheme_Linking__c ,Opportunity__r.Name,Cost_Scheme_Linking__r.Cost_Sheet_Template__r.Name,Cost_Scheme_Linking__r.Payment_Scheme__r.Name,finalize_CostSheet__c,CreatedDate
                                                    FROM Cost_Sheet__c 
                                                    WHERE Opportunity__c = :oppRec.Id
                                                    ORDER BY CreatedDate DESC];
        
        System.debug('Related Cost Sheets: ' + relatedCostSheetRecords);
        String finalizeCostSheet = '';
        List<Payment_Schedule__c> getPaymentSchemes;
        for(Cost_Sheet__c finalize : relatedCostSheetRecords){
            if(finalize.finalize_CostSheet__c == true){
                finalizeCostSheet = finalize.Id;

                getPaymentSchemes = [SELECT Id, Name, Installment__c, Agreement_Value__c, Opportunity__c, Opportunity__r.Name ,Tax_Amount__c,Due_Date__c,Pay_Date__c,Other_Charges__c,Other_Tax_Amount__c
                                    FROM Payment_Schedule__c  
                                    WHERE Opportunity__c = :oppRec.Id];
                System.debug('Payment Schedules: ' + getPaymentSchemes);
            }
        }
        
        List<Pricing_Element__c> costPricingAsstnList;
        if(finalizeCostSheet != null){
            costPricingAsstnList = [select id,Name,Pricing_Element_Master__r.Name,Amount__c,Actual_Amount__c,Discount__c,Discount_Amount__c,Tax_Amount__c,Final_Tax_Amount__c,PE_Type__c,Quantity__c,Rate__c,Total_Amount_Excluding_Tax__c from Pricing_Element__c where Cost_Sheet__c =:finalizeCostSheet];
        }
        
        
        CostSheetWrapper wrapper = new CostSheetWrapper();
        wrapper.paymentScheduleRecords = getPaymentSchemes;
        wrapper.costSheetRecords = relatedCostSheetRecords;
        wrapper.costPricingAsstnList = costPricingAsstnList;
        
        System.debug('wrapper==>'+wrapper);
        
        return wrapper;
    }
    
    
    
    @AuraEnabled
    public static costSheetAndTemplateWrapper createPaymentSchedule(Id recordId,Id costSheetId, Id selectedCostSheetTempId) {
        System.debug('Record ID: ' + recordId);
        System.debug('Processing Cost Sheet ID: ' + costSheetId);
        
        Cost_Sheet__c getCostSheet = [select id,Opportunity__c,Name,Cost_Scheme_Linking__c,finalize_CostSheet__c,Total_Pricing_Value__c, Total_Pricing_Value_Excluding_Tax__c, Total_Tax_Value__c from Cost_Sheet__c Where Id =:costSheetId Limit 1];
        getCostSheet.finalize_CostSheet__c = true;
        update getCostSheet;
        
        Id opportunityId = getCostSheet.Opportunity__c;
        Cost_Scheme_Linking__c getSchemeLinking = [select id,Payment_Scheme__c,Cost_Sheet_Template__c,Cost_Sheet_Template__r.Amount__c,Cost_Sheet_Template__r.Tax_Amount__c  from Cost_Scheme_Linking__c Where id =:getCostSheet.Cost_Scheme_Linking__c Limit 1];
        System.debug('Scheme Liking: ' + getSchemeLinking);
        
        List<Payment_Scheme_Installment__c> getPaymetSchemeRecords = [select id,Payment_Scheme__c,Payment_Scheme__r.Name,Installment__c,Name, Payment_Schedule_Master__r.No_of_Days_to_Trigger_Prior_Milestone__c, Payment_Schedule_Master__c,Payment_Schedule_Master__r.Name,Display_Order__c,Payment_Schedule_Master__r.Installment_Code__c, 
        Payment_Schedule_Master__r.Before_AOS_Demand_Letter__c,
        Payment_Schedule_Master__r.Installment_Sequence__c,Type__c,Payment_Schedule_Master__r.Description__c  from Payment_Scheme_Installment__c Where Payment_Scheme__c  =:getSchemeLinking.Payment_Scheme__c];
        System.debug('Received Record Id: ' + recordId);
        System.debug('getPaymetSchemeRecords size: ' + getPaymetSchemeRecords.size());
       // Task ts = [select id,WhatId from Task Where id =: recordId Limit 1];
        Decimal smallDisplayNum =  10000;
        for(Payment_Scheme_Installment__c psi : getPaymetSchemeRecords){
            if(psi.Display_Order__c  < smallDisplayNum){
                smallDisplayNum = psi.Display_Order__c;
            }
        }

        Decimal totalAgreementValue = 0;
        Decimal tokenAmount = 0;
        List<Payment_Schedule__c> allPaymentSchedules = new List<Payment_Schedule__c>();
        
        for(Payment_Scheme_Installment__c psi : getPaymetSchemeRecords){
            Payment_Schedule__c ps = new Payment_Schedule__c();
            Decimal rawAgreement = (getCostSheet.Total_Pricing_Value_Excluding_Tax__c / 100) * psi.Installment__c;
            Decimal rawTax = (getCostSheet.Total_Tax_Value__c / 100) * psi.Installment__c;
            
            ps.Opportunity__c = opportunityId;//ts.WhatId;
            ps.Installment__c = psi.Installment__c;
            // ps.Type__c = psi.Type__c;
            ps.Type__c = 'Agreement';
            // ps.Agreement_Value__c = (getCostSheet.Total_Pricing_Value_Excluding_Tax__c / 100) * psi.Installment__c;
            // ps.Tax_Amount__c = (getCostSheet.Total_Tax_Value__c / 100) * psi.Installment__c;
            ps.Agreement_Value__c = Math.ceil(rawAgreement);
            ps.Tax_Amount__c = Math.ceil(rawTax);

            ps.Diff_Agreement_Value__c = ps.Agreement_Value__c - rawAgreement;
            ps.Diff_Tax_Amount__c = ps.Tax_Amount__c - rawTax;
            ps.Other_Charges__c = 0;
            ps.Other_Tax_Amount__c = 0;
            //ps.Installment_Sequence__c =  psi.Payment_Schedule_Master__r.Installment_Sequence__c;
            ps.Installment_Sequence__c =  psi.Display_Order__c;
            ps.Description__c = psi.Payment_Schedule_Master__r.Description__c != null ? psi.Payment_Schedule_Master__r.Description__c : null;
            if (smallDisplayNum == psi.Display_Order__c) {
                
            } else {
                
                Date nextMonth = Date.today().addMonths(1);
                Integer lastDayOfNextMonth = Date.daysInMonth(nextMonth.year(), nextMonth.month());
                Date nextMonthLastDate = Date.newInstance(nextMonth.year(), nextMonth.month(), lastDayOfNextMonth);
                
            }
            
            
            ps.Name = psi.Payment_Schedule_Master__r.Name;
            if(ps.Name == 'Token Advance (TA) – Rs.3,12,000/'){
                tokenAmount = ps.Agreement_Value__c;
            }

            ps.Before_AOS_Demand_Letter__c = psi.Payment_Schedule_Master__r.Before_AOS_Demand_Letter__c;
            ps.No_of_Days_to_Trigger_Prior_Milestone__c = psi.Payment_Schedule_Master__r.No_of_Days_to_Trigger_Prior_Milestone__c;
            allPaymentSchedules.add(ps);
        }
        
        List<Pricing_Element__c> ammentiesPricingElements = [select Id,Cost_Sheet__c,Pricing_Element_Master__c,Pricing_Element_Master__r.Name,Type__c,Quantity__c,Amount__c,Actual_Amount__c,Total_Amount_Excluding_Tax__c,Final_Tax_Amount__c,Description__c, Sequence__c  from Pricing_Element__c Where Cost_Sheet__c =: costSheetId and Type__c ='Ammenities'];
        for(Pricing_Element__c pe : ammentiesPricingElements){
            Payment_Schedule__c ps =  new Payment_Schedule__c();
            ps.Name = pe.Pricing_Element_Master__r.Name;
            ps.Type__c =  pe.Type__c;
            ps.Opportunity__c = opportunityId;//ts.WhatId;
            ps.Agreement_Value__c = pe.Total_Amount_Excluding_Tax__c;
            ps.Tax_Amount__c = pe.Final_Tax_Amount__c;
            ps.Description__c = pe.Description__c;
            ps.Installment_Sequence__c = pe.Sequence__c;
            allPaymentSchedules.add(ps);
        }
        
        
        insert allPaymentSchedules;
        List<Cost_Sheet__c> costSheetList = [SELECT Id, Unit__c FROM Cost_Sheet__c WHERE Id =: costSheetId];
        
        List<Payment_Schedule__c> insertedPaymentSchedules = [SELECT Id, Name, Installment__c, Agreement_Value__c, Opportunity__c, Opportunity__r.Name ,Tax_Amount__c,Due_Date__c,Pay_Date__c,Other_Charges__c,Other_Tax_Amount__c
                                                            FROM Payment_Schedule__c WHERE Id IN :allPaymentSchedules];
        
        Opportunity opp = [select id,Payment_Scheme__c,Cost_Sheet_Template__c,Token_Amount__c from Opportunity where Id =: opportunityId Limit 1]; //:ts.WhatId Limit 1];
        opp.Payment_Scheme__c = getSchemeLinking.Payment_Scheme__c;
        opp.Cost_Sheet_Template__c = getSchemeLinking.Cost_Sheet_Template__c;
        opp.Token_Amount__c = tokenAmount;
        opp.Unit__c = costSheetList[0].Unit__c;
        update opp;
        
        List<Pricing_Element__c> costPricingAsstnList = [select id,Name,Pricing_Element_Master__r.Name,Amount__c,Actual_Amount__c,Discount__c,Discount_Amount__c,Tax_Amount__c,PE_Type__c,Quantity__c,Rate__c,Final_Tax_Amount__c,Total_Amount_Excluding_Tax__c,Pricing_Element_Master__c from Pricing_Element__c where Cost_Sheet__c =:getCostSheet.ID];
        
        System.debug('costPricingAsstnList==>'+costPricingAsstnList);
        
        costSheetAndTemplateWrapper wrp = new costSheetAndTemplateWrapper();
        wrp.costPricingAsstnList = costPricingAsstnList;
        wrp.paymentScheduleList = insertedPaymentSchedules;
        return wrp;
    }
    
    public class costSheetAndTemplateWrapper{
        @AuraEnabled public List<Payment_Schedule__c> paymentScheduleList{get;set;}
        @AuraEnabled public List<Pricing_Element__c> costPricingAsstnList{get;set;}
    }
    
    //added by sagar 30-05 
    @AuraEnabled
    public static CostSheetWrapper getCostSheetPreview(Id costSheetId) {
        
        System.debug('costSheetId:::>> '+costSheetId);
        Cost_Sheet__c cs = [select Id, finalize_CostSheet__c, Opportunity__c, Opportunity__r.Name from Cost_Sheet__c where Id = :costSheetId limit 1];
        
        List<Pricing_Element__c> pricingElements = [
            select id, Name, Pricing_Element_Master__r.Name, Amount__c, Actual_Amount__c, Discount__c, Discount_Amount__c,
            Tax_Amount__c, Final_Tax_Amount__c, PE_Type__c, Quantity__c, Rate__c, Total_Amount_Excluding_Tax__c
            from Pricing_Element__c where Cost_Sheet__c = :costSheetId
        ];
        
        List<Payment_Schedule__c> existingSchedules = new List<Payment_Schedule__c>();
        if (cs.finalize_CostSheet__c == true) {
            existingSchedules = [select Id, Name, Installment__c, Agreement_Value__c, Tax_Amount__c, Due_Date__c, Pay_Date__c,
                                 Other_Charges__c, Other_Tax_Amount__c, Opportunity__c, Opportunity__r.Name from Payment_Schedule__c
                                 where Opportunity__c = :cs.Opportunity__c];
        }
        
        CostSheetWrapper wrapper = new CostSheetWrapper();
        wrapper.costSheetRecords = new List<Cost_Sheet__c>{ cs };
            wrapper.paymentScheduleRecords = existingSchedules;
        wrapper.costPricingAsstnList = pricingElements;
        return wrapper;
    }
    
    
    @AuraEnabled
    public static String sendApproval(Id recordId) {
        try {
            System.debug('taskId==>'+recordId);
            // Retrieve the Task and associated Opportunity
            Task ts = [SELECT Id, WhatId,Status FROM Task WHERE Id = :recordId AND Subject =: 'Finalise Cost Sheet & Generate Payment Schedule' LIMIT 1];
            System.debug('Task: ' + ts);
            
            ts.Status = 'Completed';
            try {
                update ts;
            } catch (DmlException e) {
                System.debug('DML Exception: ' + e.getMessage());
                System.debug('Task Record ID: ' + ts.Id);
                
                System.debug('WhatId: ' + ts.WhatId);
            }
            
            Opportunity opp = [SELECT Id, Payment_Scheme__c, Cost_Sheet_Finalised__c,OwnerId, CreatedDate, Cost_Sheet_Approval_Status__c, Cost_Sheet_Template__c from Opportunity where Id = :ts.WhatId 
                            LIMIT 1];
            
            System.debug('opportunityId ==>'+opp);
            opp.Cost_Sheet_Finalised__c = true;
            opp.StageName = 'Offer Letter and Deposit Collection';
           // opp.Cost_Sheet_Approval_Status__c = 'Approved';
            update opp;  

            // Task t = new Task();
            //     t.Subject = 'Sales Head Approval and Assign to CRM';
            //     t.WhatId = opp.Id;
            //     t.OwnerId = opp.OwnerId;
            //     t.Status = 'Not Started';
            //     t.ActivityDate = opp.CreatedDate.date().addDays(4);
            //     insert t;

            return 'Success';
            
            // Opportunity opp = [SELECT Id, Payment_Scheme__c, Cost_Sheet_Template__c from Opportunity where Id = :ts.WhatId 
            //                    LIMIT 1];
            
            // System.debug('opportunityId ==>'+opp);
            // opp.Cost_Sheet_Finalised__c = true;
            // update opp;                
            
            // if (opp != null && opp.Id != null) {
            //     Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            //     req.setComments('Submitting Opportunity Cost Sheet record for approval.');
            //     req.setObjectId(opp.Id);
            //     req.setProcessDefinitionNameOrId('Opportunity_Cost_Sheet_Approval_Process');
            //     req.setSubmitterId(UserInfo.getUserId());
                
            //     Approval.ProcessResult result = Approval.process(req);
                
            //     if (result.isSuccess()) {
            //         System.debug('Approval request submitted successfully.');
            //         return 'Approval request submitted successfully for Opportunity ID: ' + opp.Id;
            //     } else {
            //         System.debug('Approval request submission failed.');
            //         return 'Approval request submission failed for Opportunity ID: ' + opp.Id;
            //     }
            // } else {
            //     throw new AuraHandledException('Opportunity not found or not associated with the given Task.');
            // }
        } catch (Exception e) {
            System.debug('Exception when submitting for approval: ' + e.getMessage());
            throw new AuraHandledException('Approval submission failed: ' + e.getMessage());
        }
    }
    
    //added by sagar 31-05 
    @AuraEnabled
    public static List<Payment_Schedule__c> generatePaymentSchedulePreview(Id costSheetId) {
        Cost_Sheet__c getCostSheet = [select Id, Opportunity__c, Total_Pricing_Value_Excluding_Tax__c, Total_Tax_Value__c, Cost_Scheme_Linking__r.Payment_Scheme__c
                                      from Cost_Sheet__c where Id = :costSheetId limit 1];
        
        List<Payment_Scheme_Installment__c> schemeInstallments = [SELECT Installment__c, Name, Type__c, Payment_Schedule_Master__r.Name,
                                                                  Payment_Schedule_Master__r.Installment_Sequence__c, Display_Order__c
                                                                  from Payment_Scheme_Installment__c
                                                                  where Payment_Scheme__c = :getCostSheet.Cost_Scheme_Linking__r.Payment_Scheme__c
                                                                  AND Type__c = 'Agreement'];
        
        List<Payment_Schedule__c> previewList = new List<Payment_Schedule__c>();
    
        for (Payment_Scheme_Installment__c psi : schemeInstallments) {
            Decimal rawAgreement = (getCostSheet.Total_Pricing_Value_Excluding_Tax__c / 100) * psi.Installment__c;
            Decimal rawTax = (getCostSheet.Total_Tax_Value__c / 100) * psi.Installment__c;
    
            Payment_Schedule__c ps = new Payment_Schedule__c();
            
            ps.Opportunity__c = getCostSheet.Opportunity__c;
            ps.Name = psi.Payment_Schedule_Master__r.Name;
            ps.Type__c = psi.Type__c;
            ps.Installment__c = psi.Installment__c;
            // ps.Agreement_Value__c = (getCostSheet.Total_Pricing_Value_Excluding_Tax__c / 100) * psi.Installment__c;
            // ps.Tax_Amount__c = (getCostSheet.Total_Tax_Value__c / 100) * psi.Installment__c;
            ps.Agreement_Value__c = Math.ceil(rawAgreement);
            ps.Tax_Amount__c = Math.ceil(rawTax);
            ps.Other_Charges__c = 0;
            ps.Other_Tax_Amount__c = 0;
            //ps.Installment_Sequence__c = psi.Payment_Schedule_Master__r.Installment_Sequence__c;
            //ps.Installment_Sequence__c = (psi.Display_Order__c != null) ? psi.Display_Order__c : 0;
            ps.Installment_Sequence__c = psi.Display_Order__c;
            ps.Diff_Agreement_Value__c = ps.Agreement_Value__c - rawAgreement;
            ps.Diff_Tax_Amount__c = ps.Tax_Amount__c - rawTax;
            
            previewList.add(ps);
        }
        
        return previewList;
    }
    @AuraEnabled
    public static void markUnitOnHold(Id costSheetId) {
        System.debug('markUnitOnHold called with costSheetId: ' + costSheetId);
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet Id is required.');
        }
        Cost_Sheet__c costSheet = [ SELECT Id,Unit__c, Opportunity__c FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1 ];

        if (costSheet.Unit__c == null) {
            throw new AuraHandledException('Unit is not associated with this Cost Sheet.');
        }
        Unit__c unitRecord = [SELECT Id, Status__c FROM Unit__c WHERE Id = :costSheet.Unit__c LIMIT 1 ];
        unitRecord.Status__c = 'Z2';
        update unitRecord;
    }
    @AuraEnabled
    public static Boolean checkStandardPaymentScheme(Id costSheetId) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet Id is required.');
        }
        Cost_Sheet__c costSheet = [SELECT Id, Cost_Scheme_Linking__c,Cost_Scheme_Linking__r.Payment_Scheme__c, Cost_Scheme_Linking__r.Payment_Scheme__r.IsStandard__c FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1 ];
        if (costSheet.Cost_Scheme_Linking__c == null) {
            return false;
        }
        if (costSheet.Cost_Scheme_Linking__r.Payment_Scheme__c == null) {
            return false;
        }
        Boolean isStandard = costSheet.Cost_Scheme_Linking__r.Payment_Scheme__r.IsStandard__c;
        System.debug('Payment Scheme IsStandard ==> ' + isStandard);
        return isStandard;
    }

    @AuraEnabled
    public static Id createEscrowAccount(Id costSheetId) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet Id is required.');
        }
        Cost_Sheet__c costSheet = [SELECT Id,Opportunity__c,Unit__c,Opportunity__r.Name,Opportunity__r.Project__c FROM Cost_Sheet__c  WHERE Id = :costSheetId LIMIT 1 ];
        if (costSheet.Opportunity__c == null) {
            throw new AuraHandledException('Opportunity is missing on Cost Sheet.');
        }
        if (costSheet.Unit__c == null) {
            throw new AuraHandledException('Unit is missing on Cost Sheet.');
        }
        Id projectId = costSheet.Opportunity__r.Project__c;
        if (projectId == null) {
            throw new AuraHandledException('Project is not tagged on the Opportunity.');
        }
        List<Escrow_Account__c> existingEscrow = [SELECT Id, Name,Opportunity__c, Project__c, Unit__c,Status__c FROM Escrow_Account__c WHERE Project__c = :projectId AND Status__c = true LIMIT 1];
        Escrow_Account__c escrow;
        if (!existingEscrow.isEmpty()) {
            escrow = existingEscrow[0];
            escrow.Opportunity__c = costSheet.Opportunity__c;
            escrow.Unit__c = costSheet.Unit__c;
            update escrow;
        } else {
            escrow = new Escrow_Account__c();
            escrow.Opportunity__c = costSheet.Opportunity__c;
            escrow.Project__c = projectId;
            escrow.Unit__c = costSheet.Unit__c;
            escrow.Status__c = true;

            insert escrow;
        }

        System.debug('Escrow Account ==> ' + escrow );
        return escrow.Id;
    }
}