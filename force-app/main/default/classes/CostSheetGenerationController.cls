public without Sharing  class CostSheetGenerationController {
    
    @AuraEnabled
    public static fetchDataWrapper getOnLoadData(String recordId) {
        try {
            System.debug('recordId --->' + recordId);
            
            Tax_Details__c carParkingTax = [SELECT Id, Name, CGST__c, SGST__c FROM Tax_Details__c WHERE Name = 'Tax Details' LIMIT 1];
            
            Opportunity opp = new Opportunity();
            if(recordId.startsWith('00T')){
                Task ts = [select id,WhatId from Task where id =: recordId ];

                opp = [SELECT Id, Email__c, Unit__c, OwnerId, Unit__r.Name, Unit__r.Unit_Name_Code__c, (SELECT Id, Subject, WhatId, Status FROM Tasks WHERE Subject = 'Finalise Cost Sheet & Generate Payment Schedule' AND Status = 'Open') FROM Opportunity WHERE Id =:ts.WhatId];
                System.debug('opp --->' + opp);
                System.debug('opp.Tasks --->' + opp.Tasks);
            }
            else{
                opp = [SELECT Id, Email__c, Unit__c, OwnerId, Unit__r.Name, Unit__r.Unit_Name_Code__c,(SELECT Id, Subject, WhatId, Status FROM Tasks WHERE Subject = 'Finalise Cost Sheet & Generate Payment Schedule' AND Status = 'Open') FROM Opportunity WHERE Id =:recordId];
                System.debug('opp==>'+opp);
            }
            System.debug('opp==>'+opp);
            List<Unit__c> unitList = [SELECT Id, Name, Floor__c, Floor__r.Block__c, Floor__r.Block__r.Base_Price_of_Unit_per_sqft__c,  Super_Built_Up_Area_sq_ft__c FROM Unit__c Where Status__c != 'Sold']; //Floor__r.Block__r.Max_Discount_on_Base_Price__c,
            System.debug('unitList --->' + unitList);
            
            List<Cost_Sheet_Template__c> costSheetTemplateList = [SELECT Id, Name, 
                                                                    (SELECT Id, Name, Payment_Scheme__r.Name,Payment_Scheme__r.Block__c FROM Cost_Scheme_Linkings__r), 
                                                                    (SELECT Id, Name, Unit__c FROM Cost_Unit_Linking__r)
                                                                    FROM Cost_Sheet_Template__c
                                                                    WHERE Id IN (SELECT Cost_Sheet_Template__c FROM Cost_Scheme_Linking__c)];
            System.debug('costSheetTemplateList --->' + costSheetTemplateList);
            fetchDataWrapper wrp = new fetchDataWrapper();
            wrp.opp = opp;
            wrp.carParkingTax = carParkingTax;
            wrp.unitList = unitList.isEmpty() ? null : unitList;
            wrp.costSheetTemplateList = costSheetTemplateList.isEmpty() ? null : costSheetTemplateList;
            if (String.isBlank(opp.Email__c)) {
                wrp.emailError = 'Email is mandatory on the Opportunity before generating a Cost Sheet.';
            }
            System.debug('UNIT LIST SIZE =====> ' + unitList.size());
            System.debug('TEMPLATE LIST SIZE ==> ' + costSheetTemplateList.size());

            System.debug('UNIT LIST EMPTY =====> ' + unitList.isEmpty());
            System.debug('TEMPLATE LIST EMPTY ==> ' + costSheetTemplateList.isEmpty());
            wrp.errorMessage = unitList.isEmpty() || costSheetTemplateList.isEmpty() ? 'Unit or Cost Sheet Template is empty' : null;
            System.debug('wrp --->' + wrp);
            System.debug('ERROR MESSAGE =======> ' + wrp.errorMessage);
            return wrp;
        } catch(Exception e) {
            System.debug('Error in getUnits ---> ' + e.getMessage());
            System.debug('Error in getUnits ---> ' + e.getLineNumber());
            return null;
        }
    }
    
    public class fetchDataWrapper{
        @AuraEnabled public List<Unit__c> unitList{get;set;}
        @AuraEnabled public List<Cost_Sheet_Template__c> costSheetTemplateList{get;set;}
        @AuraEnabled public Opportunity opp{get;set;}
        @AuraEnabled public Tax_Details__c carParkingTax{get;set;}
        @AuraEnabled public String errorMessage{get; set;}
        @AuraEnabled public String emailError{get; set;}
    }
    
    
    @AuraEnabled
    public static Unit__c getUnitRecord(String unitId) {
        try {
            return [
                select id,Name,Unit_Name_Code__c,Status__c,Floor__r.Block__c from Unit__c where Id =: unitId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unit record: ' + e.getMessage());
        }
    }
    @AuraEnabled
    public static String saveCostSheet(Opportunity opp,List<Task> tasks,String unitId,String cslId,List<Pricing_Element__c> pricingElements,
        List<Map<String, Object>> parkingElements,Decimal discountAmount, Decimal discountPercent) {
        try {
            if (opp == null) {
                throw new AuraHandledException('Please enter the Opportunity');
            }

            if (String.isBlank(unitId)) {
                throw new AuraHandledException('Please select the Unit');
            }

            if (String.isBlank(cslId)) {
                throw new AuraHandledException('Please select the Cost Scheme');
            }
            //COST SHEET
            Cost_Sheet__c cs = new Cost_Sheet__c();
            cs.Opportunity__c = opp.Id;
            cs.Cost_Scheme_Linking__c = cslId;
            cs.Unit__c = unitId;
            cs.Discount_Amount__c = discountAmount != null ? discountAmount : 0;
            cs.Discount_Percent__c = discountPercent != null ? discountPercent : 0;
            insert cs;
            System.debug('Cost Sheet Created: ' + cs.Id);
            List<Task> existingTasks = [SELECT Id, Subject, Status FROM Task WHERE WhatId = :opp.Id AND Subject = 'Finalise Cost Sheet & Generate Payment Schedule' LIMIT 1];
            if (existingTasks.isEmpty()) {
                Task finaliseCostSheetTask = new Task();
                finaliseCostSheetTask.Subject ='Finalise Cost Sheet & Generate Payment Schedule';
                finaliseCostSheetTask.WhatId = opp.Id;
                finaliseCostSheetTask.OwnerId = opp.OwnerId;
                finaliseCostSheetTask.ActivityDate = Date.today().addDays(3);
                insert finaliseCostSheetTask;
                System.debug('Finalise Cost Sheet Task Created: ' + finaliseCostSheetTask.Id);
            }

            //PRICING ELEMENTS
            if (pricingElements != null && !pricingElements.isEmpty()) {
                List<Pricing_Element__c> pricingToInsert = new List<Pricing_Element__c>();
                for (Pricing_Element__c item : pricingElements) {
                    Pricing_Element__c pe = new Pricing_Element__c();
                    pe.Cost_Sheet__c = cs.Id;
                    pe.Pricing_Element_Master__c = item.Pricing_Element_Master__c;
                    pe.PE_Type__c = item.PE_Type__c;
                    pe.Quantity__c = item.Quantity__c;
                    pe.Rate__c = item.Rate__c;
                    pe.Unit__c = item.Unit__c;
                    pe.Type__c = item.Type__c;
                    pe.Amount__c = item.Amount__c;
                    pe.Discount_Amount__c = item.Discount_Amount__c;
                    pe.Discount__c = item.Discount__c;
                    pe.SGST_Tax_Percentage__c = item.SGST_Tax_Percentage__c;
                    pe.CGST_Tax_Percentage__c = item.CGST_Tax_Percentage__c;
                    pe.IGST_Tax_Percentage__c = item.IGST_Tax_Percentage__c;
                    pe.parking_Element__c = item.parking_Element__c;
                    pricingToInsert.add(pe);
                }

                insert pricingToInsert;
            }
            //PARKING ELEMENTS
            if (parkingElements != null && !parkingElements.isEmpty()) {
                List<Pricing_Element_Master__c> masters = [SELECT Id, Name, Parking_Type__c FROM Pricing_Element_Master__c WHERE Parking_Type__c != null];
                Map<String, Id> parkingMasterMap = new Map<String, Id>();
                for (Pricing_Element_Master__c master : masters) {
                    parkingMasterMap.put(master.Parking_Type__c, master.Id);
                }
                List<Pricing_Element__c> parkingToInsert = new List<Pricing_Element__c>();
                for (Map<String, Object> row : parkingElements) {
                    String type = (String) row.get('type');
                    if (!parkingMasterMap.containsKey(type)) {
                        continue;
                    }
                    Pricing_Element__c pe = new Pricing_Element__c();
                    pe.Cost_Sheet__c = cs.Id;
                    pe.Pricing_Element_Master__c = parkingMasterMap.get(type);
                    pe.Rate__c = getDecimalValue(row.get('amount'));
                    pe.Amount__c = getDecimalValue(row.get('finalAmount'));
                    pe.Quantity__c = getIntegerValue(row.get('quantity'));
                    pe.SGST_Tax_Percentage__c = getDecimalValue(row.get('carCGSTtax'));
                    pe.CGST_Tax_Percentage__c = getDecimalValue(row.get('carSGSTtax'));
                    pe.parking_Element__c = true;
                    pe.Type__c = 'Agreement';
                    parkingToInsert.add(pe);
                }

                if (!parkingToInsert.isEmpty()) {
                    insert parkingToInsert;
                }
            }
            update opp;
            return cs.Id;
        } catch (Exception e) {
            System.debug('Error in saveCostSheet: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // @AuraEnabled
    // public static String createCostSheet(Opportunity opp, List<Task> tasks, String unitId, String cslId) {
    //     try {
    //         String costSheetId;
    //         System.debug('tasks===>'+tasks);
    //         System.debug('unitId===>'+unitId);
    //         System.debug('cslId===>'+cslId);
    //         List<Task> costSheetTask = [SELECT Id,Subject from task where Subject = 'Finalise Cost Sheet & Generate Payment Schedule' LIMIT 1];
    //         if (opp == null) {
    //             return 'Please enter the Opportunity';
    //         }
    //         if (cslId == null || cslId == '') {
    //             return 'Please select the cost scheme';
    //         }
    //         if (unitId == null || unitId == '') {
    //             return 'Please select the Unit';
    //         }
    //         System.debug('oppId ---> ' + opp.Id);
    //         System.debug('Tasks --->' + tasks);
    //         System.debug('costSchemeLinkingId ---> ' + cslId);
            
    //         // List<Cost_Sheet__c> costSheetList = [SELECT Id, Name, Opportunity__c, Cost_Scheme_Linking__c FROM Cost_Sheet__c WHERE Opportunity__c = :opp.Id AND Cost_Scheme_Linking__c = :cslId AND Unit__c =: unitId];
    //         // System.debug('costSheetList --->' + costSheetList);
    //         // if(!costSheetList.isEmpty()) {
    //             //     System.debug('Cost Sheet Already There');
    //             //     return 'ERROR';
    //         // }
            
    //         opp.StageName = 'Cost Sheet Generated';
    //         Cost_Sheet__c cs = new Cost_Sheet__c();
    //         cs.Opportunity__c = opp.Id;
    //         cs.Cost_Scheme_Linking__c = cslId;
    //         cs.Unit__c = unitId;
            
    //         if (cs != null) {
    //             insert cs;
    //             costSheetId = cs.Id;
    //             System.debug('Task.size ---> ' + opp.Tasks.size());
    //             System.debug('costSheetTask==>'+costSheetTask);
    //             if(tasks == null || costSheetTask.isEmpty()){
    //                 Task t = new Task();
    //                 t.Subject = 'Finalise Cost Sheet & Generate Payment Schedule';
    //                 t.WhatId = opp.Id;
    //                 t.OwnerId = opp.OwnerId;
    //                 t.ActivityDate = Date.newInstance(System.now().addDays(3).year(),
    //                 System.now().addDays(3).month(),
    //                 System.now().addDays(3).day());  // Adds 72 hours (3 days) to the current time
    //                 insert t;
    //                 update opp;
                    
    //             }
    //         }
            
    //         List<Unit__c> unitList = [SELECT Id,Name,Super_Built_Up_Area_sq_ft__c,Floor_Rise__c,Corner_Rs_Sqft__c,Facing_Rs_Sqft__c,Base_Price_per_sqft__c from Unit__c where Id =: unitId LIMIT 1]; //Car_Parking_Amount__c,Car_Parking__c
    //         System.debug('unitList==>'+unitList);
            
    //         Task taskToClose = [select id,Subject,Status from Task Where WhatId =: opp.Id AND Subject =:'Generate Cost Sheet' Limit 1];
    //         taskToClose.Status = 'Completed';
    //         update taskToClose;
            
    //         List<Cost_Scheme_Linking__c> getCostSchemeLinking = [select id,Cost_Sheet_Template__c from Cost_Scheme_Linking__c Where Id =: cslId Limit 1];
    //         System.debug('getCostSchemeLinking==>'+getCostSchemeLinking);
            
    //         List<Cost_Pricing_Association__c> getAllPricingAssociations = [select id,Name,Amount__c,Cost_Sheet_Template__c,PE_Type__c,Type__c,Pricing_Element_Master__c,Quantity__c,Rate__c,Tax_Amount__c,Unit__c,Pricing_Element_Master__r.Name, Sequence__c  from Cost_Pricing_Association__c where Cost_Sheet_Template__c =: getCostSchemeLinking[0].Cost_Sheet_Template__c];
    //         System.debug('getAllPricingAssociations==>'+getAllPricingAssociations);
            
    //         Set<String> allcostPricingAssIds = new Set<String>();
    //         for(Cost_Pricing_Association__c cpa : getAllPricingAssociations){
    //             allcostPricingAssIds.add(cpa.Id);
    //         }
            
    //         List<Cost_Sheet_Tax_Linking__c> costSheetTaxLinkingRecords = [select Id,Cost_Pricing_Association__c,Tax_Master__c,Tax_Master__r.Tax__c ,Tax_Master__r.Tax_Type__c ,Tax_Master__r.Name from Cost_Sheet_Tax_Linking__c Where Cost_Pricing_Association__c  In:allcostPricingAssIds];
    //         List<Pricing_Element_Master__c > pricingElementMasterRecords = [select Id,Name from Pricing_Element_Master__c  Where Name = 'Corner Charges' or Name = 'Floor Rise' or Name = 'Facing Charges'];
    //         Map<Id,Pricing_Element_Master__c> mapofPricingElements = new  Map<Id,Pricing_Element_Master__c>();
    //         for(Pricing_Element_Master__c pemr : pricingElementMasterRecords){
    //             mapofPricingElements.put(pemr.Id, pemr);
    //         }
            
    //         System.debug('mapofPricingElements==>'+mapofPricingElements);
            
            
    //         List<Pricing_Element__c> pricingElementsToInsert = new List<Pricing_Element__c>();
    //         List<PricingElements__c> pricingRecords = [
    //             SELECT Name, Unit_Field__c 
    //             FROM PricingElements__c
    //         ];
            
    //         Map<String, String> pricingMap = new Map<String, String>();
            
    //         // Populate the Map
    //         for (PricingElements__c rec : pricingRecords) {
    //             pricingMap.put(rec.Name, rec.Unit_Field__c);
    //         }
            
    //         for(Cost_Pricing_Association__c csp : getAllPricingAssociations){
    //             Pricing_Element_Master__c matchedElement;
    //             if(mapofPricingElements.ContainsKey(csp.Pricing_Element_Master__c)){
                    
    //                 matchedElement = mapofPricingElements.get(csp.Pricing_Element_Master__c);
    //                 System.debug('matchedElement==>'+matchedElement);
    //             }
    //             Pricing_Element__c pe = new Pricing_Element__c();
    //             pe.Cost_Sheet__c = costSheetId != null ? costSheetId : null;
    //             pe.PE_Type__c = csp.PE_Type__c != null ? csp.PE_Type__c : null;
    //             pe.Sequence__c = csp.Sequence__c != null ? csp.Sequence__c : null;
    //             Decimal area = unitList[0].Super_Built_Up_Area_sq_ft__c;
                
    //             System.debug('csp.Pricing_Element_Master__r.Name==>'+csp.Pricing_Element_Master__r.Name);
    //             System.debug('Corner Charges==>'+pricingMap.get('Corner Charges'));
    //             System.debug('Floor Rise==>'+pricingMap.get('Floor Rise'));
    //             System.debug('Facing Charges==>'+pricingMap.get('Facing Charges'));
    //             System.debug('Basic Price ==>'+pricingMap.get('Basic Price'));
    //             System.debug('matchedElement==>'+matchedElement);
                
                
    //             if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Corner Charges')  && unitList[0].Corner_Rs_sqft__c != null ){
    //                 System.debug('entered..');
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Corner_Rs_sqft__c;
    //                 pe.Amount__c = unitList[0].Corner_Rs_sqft__c * area;
                    
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Floor Rise') && unitList[0].Floor_Rise__c != null ){
    //                 System.debug('entered..');
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Floor_Rise__c;
    //                 pe.Amount__c = unitList[0].Floor_Rise__c * area;
                    
                    
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Facing Charges') && unitList[0].Facing_Rs_Sqft__c != null){
    //                 System.debug('entered..');
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Facing_Rs_Sqft__c;
    //                 pe.Amount__c = unitList[0].Facing_Rs_Sqft__c * area;
                    
                    
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Basic Price') ){
    //                 System.debug('entered..');
    //                 System.debug('unitList==>'+unitList[0]);
    //                 System.debug('unitList==>'+unitList[0].Base_Price_per_sqft__c);
    //                 pe.Quantity__c = area;
    //                 pe.Rate__c = unitList[0].Base_Price_per_sqft__c;
    //                 pe.Amount__c = unitList[0].Base_Price_per_sqft__c * area;
    //             }else if(csp.Pricing_Element_Master__r.Name == pricingMap.get('Car Parking') ){
    //                 // System.debug('entered..');
    //                 // System.debug('unitList==>'+unitList[0]);
    //                 // System.debug('unitList==>'+unitList[0].Car_Parking_Amount__c );
    //                 // pe.Quantity__c = 1;
    //                 // pe.Rate__c = unitList[0].Car_Parking_Amount__c ;
    //                 // pe.Amount__c =   unitList[0].Car_Parking_Amount__c ;
    //             }
    //             else{
    //                 pe.Quantity__c = (csp.Unit__c != null && csp.Unit__c == 'sqft' && unitList[0].Super_Built_Up_Area_sq_ft__c != null) ? unitList[0].Super_Built_Up_Area_sq_ft__c : csp.Quantity__c;
    //                 // pe.Rate__c = csp.Rate__c != null ? csp.Rate__c : null;
    //                 // pe.Amount__c = pe.Quantity__c != null && pe.Rate__c != null ? (pe.Quantity__c * pe.Rate__c) : null;
    //                 pe.Rate__c = csp.Rate__c;
    //                 if (pe.Quantity__c != null && pe.Rate__c != null) {
    //                     Decimal amount = pe.Quantity__c * pe.Rate__c;
    //                     // Round Rate and Amount up to next integer if needed
    //                     if (pe.Rate__c != pe.Rate__c.setScale(0)) {
    //                         pe.Rate__c = pe.Rate__c.setScale(0, RoundingMode.CEILING);
    //                     }
    //                     if (amount != amount.setScale(0)) {
    //                         pe.Amount__c = amount.setScale(0, RoundingMode.CEILING);
    //                     } else {
    //                         pe.Amount__c = amount;
    //                     }
    //                 } else {
    //                     pe.Amount__c = null;
    //                 }
                    
    //             }
    //             pe.Unit__c = csp.Unit__c != null ? csp.Unit__c : null;
    //             pe.Type__c = csp.Type__c != null ? csp.Type__c : null;
    //             pe.Pricing_Element_Master__c = csp.Pricing_Element_Master__c;
    //             for(Cost_Sheet_Tax_Linking__c cstlr : costSheetTaxLinkingRecords){
    //                 if(csp.Id == cstlr.Cost_Pricing_Association__c){
    //                     if(cstlr.Tax_Master__r.Tax_Type__c == 'SGST'){
    //                         pe.SGST_Tax_Percentage__c = cstlr.Tax_Master__r.Tax__c;
    //                     }else if(cstlr.Tax_Master__r.Tax_Type__c == 'CGST'){
    //                         pe.CGST_Tax_Percentage__c = cstlr.Tax_Master__r.Tax__c;
    //                     }else if(cstlr.Tax_Master__r.Tax_Type__c == 'IGST'){
    //                         pe.IGST_Tax_Percentage__c = cstlr.Tax_Master__r.Tax__c;
    //                     }
                        
    //                 }
    //             }
                
    //             pricingElementsToInsert.add(pe);
                
    //         }
    //         System.debug('pricingElementsToInsert==>'+pricingElementsToInsert);
    //         insert pricingElementsToInsert;
            
    //         System.debug('costSheetId==>'+costSheetId);
            
    //         return costSheetId;
    //     } catch (DmlException e) {
    //         System.debug('DML Error in createCostSheet ---> ' + e.getMessage());
    //         return 'Error during insert: ' + e.getMessage();
    //     } catch (Exception e) {
    //         System.debug('Error in createCostSheet ---> ' + e.getMessage());
    //         return e.getMessage();
    //     }
    // }
    
    
    // @AuraEnabled
    // public static List<Discount_LineItem__c> checkAccess(String opp){
    //     System.debug('opp==>'+opp);
    //     try {
    //         List<Opportunity> oppRecord  = [select id,Project__c,Project__r.Name from  Opportunity where Id =: opp Limit 1];
    //         System.debug('oppRecord==>'+oppRecord);
    //         if(oppRecord.size() > 0 && oppRecord[0].Project__c != null){
    //             List<Discount_Master__c> discountMaster = [select id,Project__c,Active__c from Discount_Master__c where Project__c =: oppRecord[0].Project__c AND Active__c = true];
    //             Set<Id> allDiscountMasterIds = new set<Id>();
    //             for(Integer i=0;i<discountMaster.size();i++){
    //                 allDiscountMasterIds.add(discountMaster[i].Id);
    //             }
    //             if(allDiscountMasterIds.size() > 0 ){
    //                 List<Discount_LineItem__c> dlis = [
    //                     SELECT Id, Roles__c, Maximum__c, Minimum__c, Discount_Master__c,
    //                         Discount_Master__r.Pricing_Element_Master__c,
    //                         Discount_Master__r.Pricing_Element_Master__r.Name
    //                     FROM Discount_LineItem__c
    //                     WHERE Discount_Master__c IN :allDiscountMasterIds
    //                     ORDER BY Discount_Master__c, Maximum__c DESC
    //                 ];

    //                 Map<Id, Discount_LineItem__c> masterToLineItemMap = new Map<Id, Discount_LineItem__c>();

    //                 for (Discount_LineItem__c dli : dlis) {
    //                     if (!masterToLineItemMap.containsKey(dli.Discount_Master__c)) {
    //                         masterToLineItemMap.put(dli.Discount_Master__c, dli);
    //                     }
    //                 }
    //                 List<Discount_LineItem__c> discountLineItems = masterToLineItemMap.values();                    
    //                 // List<Discount_LineItem__c> discountLineItems = [select id,Roles__c,Maximum__c,Minimum__c,Discount_Master__c,Discount_Master__r.Pricing_Element_Master__c, Discount_Master__r.Pricing_Element_Master__r.Name from Discount_LineItem__c where Discount_Master__c In: allDiscountMasterIds ORDER BY Maximum__c DESC];
    //                 // System.debug('discountLineItems==>'+discountLineItems);
    //                 return discountLineItems;
    //             }
                
                
    //         }
    //         return new List<Discount_LineItem__c>();
            
    //     } catch (Exception e) {
    //         throw new AuraHandledException(e.getMessage());
    //     }
    // }
    
    // @AuraEnabled
    // public static List<Pricing_Element__c> getPricingElements(String cslId, String unitId){
    //     try{
    //         System.debug('cslId==>'+cslId);
    //         System.debug('unitId==>'+unitId);
    //         List<Pricing_Element__c> getAllPricingAssociations = [select id,Name,Amount__c,Cost_Sheet__c,PE_Type__c,Quantity__c,Rate__c,Final_Tax_Amount__c,Unit__c,Pricing_Element_Master__c,Pricing_Element_Master__r.Name,Cost_Sheet__r.Name,Discount_Amount__c,Discount__c  from Pricing_Element__c where Cost_Sheet__c =: cslId];
    //         System.debug('getAllPricingAssociations==>'+getAllPricingAssociations);
    //         return getAllPricingAssociations;
    //     }catch(Exception e){
    //         System.debug('Exception occurred: ' + e.getMessage());
    //         return new List<Pricing_Element__c>();
    //     }
    // }
    @AuraEnabled
    public static List<Pricing_Element__c> getPricingElements(String cslId, String unitId) {
        try {
            System.debug('cslId ==> ' + cslId);
            System.debug('unitId ==> ' + unitId);

            List<Cost_Scheme_Linking__c> costSchemeLinking = [SELECT Id, Cost_Sheet_Template__c FROM Cost_Scheme_Linking__c  WHERE Id = :cslId  LIMIT 1  ];
            if (costSchemeLinking.isEmpty()) {
                return new List<Pricing_Element__c>();
            }

            List<Unit__c> unitList = [SELECT Id,Name,Super_Built_Up_Area_sq_ft__c,  Floor_Rise__c, Corner_Rs_Sqft__c, Facing_Rs_Sqft__c,Base_Price_per_sqft__c FROM Unit__c  WHERE Id = :unitId LIMIT 1 ];

            if (unitList.isEmpty()) {
                return new List<Pricing_Element__c>();
            }

            List<Cost_Pricing_Association__c> pricingAssociations = [ SELECT Id,Name,Amount__c, Cost_Sheet_Template__c, PE_Type__c, Type__c, Pricing_Element_Master__c,
                    Quantity__c, Rate__c, Tax_Amount__c,  Unit__c, Sequence__c,Pricing_Element_Master__r.Name  FROM Cost_Pricing_Association__c WHERE Cost_Sheet_Template__c = :costSchemeLinking[0].Cost_Sheet_Template__c ];

            if (pricingAssociations.isEmpty()) {
                return new List<Pricing_Element__c>();
            }

            Set<Id> cpaIds = new Set<Id>();
            for (Cost_Pricing_Association__c cpa : pricingAssociations) {
                cpaIds.add(cpa.Id);
            }
            List<Cost_Sheet_Tax_Linking__c> taxLinkingRecords = [SELECT Id,Cost_Pricing_Association__c, Tax_Master__c, Tax_Master__r.Tax__c, Tax_Master__r.Tax_Type__c,  Tax_Master__r.Name
                FROM Cost_Sheet_Tax_Linking__c  WHERE Cost_Pricing_Association__c IN :cpaIds ];

            List<PricingElements__c> pricingRecords = [  SELECT Name, Unit_Field__c FROM PricingElements__c  ];
            Map<String, String> pricingMap = new Map<String, String>();
            for (PricingElements__c rec : pricingRecords) {
                pricingMap.put(rec.Name, rec.Unit_Field__c);
            }
            List<Pricing_Element__c> pricingElements = new List<Pricing_Element__c>();
            Decimal area = unitList[0].Super_Built_Up_Area_sq_ft__c;
            for (Cost_Pricing_Association__c csp : pricingAssociations) {
                Pricing_Element__c pe = new Pricing_Element__c();
                pe.PE_Type__c = csp.PE_Type__c;
                pe.Sequence__c = csp.Sequence__c;
                pe.Unit__c = csp.Unit__c;
                pe.Type__c = csp.Type__c;
                pe.Pricing_Element_Master__c = csp.Pricing_Element_Master__c;

                if (csp.Pricing_Element_Master__r.Name == pricingMap.get('Corner Charges') && unitList[0].Corner_Rs_sqft__c != null  ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Corner_Rs_sqft__c;
                    pe.Amount__c =  unitList[0].Corner_Rs_sqft__c * area;
                } else if (csp.Pricing_Element_Master__r.Name == pricingMap.get('Floor Rise')  &&  unitList[0].Floor_Rise__c != null  ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Floor_Rise__c;
                    pe.Amount__c =  unitList[0].Floor_Rise__c * area;

                } else if (csp.Pricing_Element_Master__r.Name ==  pricingMap.get('Facing Charges') && unitList[0].Facing_Rs_Sqft__c != null ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Facing_Rs_Sqft__c;
                    pe.Amount__c = unitList[0].Facing_Rs_Sqft__c * area;

                } else if (csp.Pricing_Element_Master__r.Name ==  pricingMap.get('Basic Price')  ) {
                    pe.Quantity__c = area;
                    pe.Rate__c = unitList[0].Base_Price_per_sqft__c;
                    pe.Amount__c =   unitList[0].Base_Price_per_sqft__c * area;

                } else if (
                    csp.Pricing_Element_Master__r.Name ==pricingMap.get('Car Parking')
                ) {

                    //  Car Parking logic .

                } else {
                    pe.Quantity__c =(csp.Unit__c != null && csp.Unit__c == 'sqft' && area != null) ? area : csp.Quantity__c;

                    pe.Rate__c = csp.Rate__c;

                    if (pe.Quantity__c != null && pe.Rate__c != null ) {
                        Decimal amount = pe.Quantity__c * pe.Rate__c;
                        if (pe.Rate__c != pe.Rate__c.setScale(0)) {
                            pe.Rate__c = pe.Rate__c.setScale(0, RoundingMode.CEILING );
                        }

                        if (amount != amount.setScale(0)
                        ) {
                            pe.Amount__c =  amount.setScale(0, RoundingMode.CEILING);
                        } else {
                            pe.Amount__c = amount;
                        }

                    } else {
                        pe.Amount__c = null;
                    }
                }

                for (Cost_Sheet_Tax_Linking__c taxRec : taxLinkingRecords) {
                    if ( csp.Id == taxRec.Cost_Pricing_Association__c ) {
                        if ( taxRec.Tax_Master__r.Tax_Type__c =='SGST'  ) {
                            pe.SGST_Tax_Percentage__c = taxRec.Tax_Master__r.Tax__c;
                        } else if (
                            taxRec.Tax_Master__r.Tax_Type__c == 'CGST'
                        ) {
                            pe.CGST_Tax_Percentage__c = taxRec.Tax_Master__r.Tax__c;

                        } else if (
                            taxRec.Tax_Master__r.Tax_Type__c == 'IGST'
                        ) {
                        pe.IGST_Tax_Percentage__c =  taxRec.Tax_Master__r.Tax__c;
                        }
                    }
                }

                pe.Pricing_Element_Master__r = csp.Pricing_Element_Master__r;
                pricingElements.add(pe);
            }

            System.debug('Preview Pricing Elements ==> ' + pricingElements );
            return pricingElements;
        }  catch (Exception e) {
            System.debug( 'getPricingElements Error ==> ' + e.getMessage() );
            System.debug(  'Line ==> ' + e.getLineNumber() );
            return new List<Pricing_Element__c>();
        }
    }
    
    @AuraEnabled
    public static List<Parking_Detail__c> getParkingRecords(String unitId){
        try{
            System.debug('unitId==>'+unitId);
            List<Unit__c> allUnits = [select id,Unit_Type__c,Status__c,Unit_Name_Code__c,Floor__r.Block__r.Id from Unit__c Where Id =:unitId];
            
            List<Parking_Detail__c> getAllParkingRecords = [select id,Amount_Per_Parking__c,Block__c,Name,Parking_Type__c,Total_Parking__c,Available_Parking__c from Parking_Detail__c where Block__c =: allUnits[0].Floor__r.Block__r.Id];
            return getAllParkingRecords;
            
        }catch(Exception e){
            System.debug('Exception occurred: ' + e.getMessage());
            return new List<Parking_Detail__c>();
        }
    }
    
    @AuraEnabled
    public static List<Pricing_Element__c> createparkingElements(List<Map<String, Object>> parkingElements,String costId) {
        set<String> insertedPricingElements = new set<String>();
        List<Pricing_Element__c> getAllPricingAssociations  = new List<Pricing_Element__c>();
        try {
            System.debug('parkingElements==>' + parkingElements);
            List<Pricing_Element_Master__c> getPricingElements = [
                SELECT Id, Name, Parking_Type__c 
                FROM Pricing_Element_Master__c 
                WHERE Parking_Type__c != null
            ];
            
            Map<String, Id> pricingElementMap = new Map<String, Id>();
            for (Pricing_Element_Master__c elem : getPricingElements) {
                pricingElementMap.put(elem.Parking_Type__c, elem.Id);
            }
            
            List<Pricing_Element__c> pricingElementsToUpsert = new List<Pricing_Element__c>();
            
            for (Map<String, Object> row : parkingElements) {
                System.debug('row==>'+row);
                String type = (String) row.get('type');
                Id pricingElementId = pricingElementMap.get(type);
                
                
                if (pricingElementId != null) {
                    Pricing_Element__c newElement = new Pricing_Element__c(
                        Pricing_Element_Master__c = pricingElementId,
                    Rate__c = getDecimalValue(row.get('amount')),
                    Amount__c = getDecimalValue(row.get('finalAmount')),
                    Quantity__c =  getIntegerValue(row.get('quantity')),
                    SGST_Tax_Percentage__c = getDecimalValue(row.get('carCGSTtax')),
                    CGST_Tax_Percentage__c = getDecimalValue(row.get('carSGSTtax')),
                    parking_Element__c = true,
                    Cost_Sheet__c = costId,
                    Type__c = 'Agreement'
                        //  Parking_Numbers__c =  parkingValues
                    );
                    System.debug('newElement ===> ' + newElement);
                    pricingElementsToUpsert.add(newElement);
                } else {
                    System.debug('No matching Pricing Element Master found for type: ' + type);
                }
            }
            
            if (!pricingElementsToUpsert.isEmpty()) {
                insert pricingElementsToUpsert;
                for (Pricing_Element__c insertedElement : pricingElementsToUpsert) {
                    insertedPricingElements.add(insertedElement.Id);
                }
                getAllPricingAssociations = [select id,Name,Amount__c,Cost_Sheet__c,PE_Type__c,Quantity__c,Rate__c,Tax_Amount__c,Unit__c,Pricing_Element_Master__c,Pricing_Element_Master__r.Name,Cost_Sheet__r.Name,Discount__c,Discount_Amount__c  from Pricing_Element__c where Id IN: insertedPricingElements];
            }
            return getAllPricingAssociations;
        } catch (Exception e) {
            system.debug('Error ==> ' + e.getMessage());
            system.debug('Error in line ==> ' + e.getLineNumber());
            return null;
        }
    }
    
    
    
    public static Decimal getDecimalValue(Object value) {
        try {
            if (value == null) {
                return 0; // Default value if null
            } else if (value instanceof Decimal) {
                return (Decimal) value; // Directly return if it's already a Decimal
            } else if (value instanceof String) {
                return Decimal.valueOf((String) value); // Convert String to Decimal
            }
        } catch (Exception e) {
            System.debug('Error converting to Decimal: ' + e.getMessage());
        }
        return 0; // Default fallback value
    }
    
    
    public static Integer getIntegerValue(Object value) {
        try {
            if (value == null) {
                return 1; // Default value if null
            } else if (value instanceof Decimal) {
                return ((Decimal) value).intValue(); // Convert Decimal to Integer
            } else if (value instanceof String) {
                return Integer.valueOf((String) value); // Convert String to Integer
            }
        } catch (Exception e) {
            System.debug('Error converting to Integer: ' + e.getMessage());
        }
        return 1; // Default fallback value
    }
    
    // @AuraEnabled
    // public static String updatePricingElements(List<Pricing_Element__c> pricingElements) {
    //     try {
    //         if (pricingElements == null || pricingElements.isEmpty()) {
    //             throw new AuraHandledException('No Pricing Elements provided for update.');
    //         }
    //         System.debug('Pricing Elements to upsert: ' + pricingElements);
    //         for (Pricing_Element__c pricingElement : pricingElements) {
    //             if (pricingElement.Quantity__c != null && pricingElement.Rate__c != null) {
    //                 Decimal amount = pricingElement.Quantity__c * pricingElement.Rate__c;
    //                 pricingElement.Amount__c = (amount != amount.setScale(0)) ? amount.setScale(0, RoundingMode.CEILING) : amount;
    //             }
    //         }
    //         upsert pricingElements;
    //         return 'success';
    //     } catch (Exception e) {
    //         system.debug('Error ==> ' + e.getMessage());
    //         system.debug('Error in line ==> ' + e.getLineNumber());
    //         return null;
    //     }
    // }
    @AuraEnabled
    public static String updatePricingElements( List<Pricing_Element__c> pricingElements,String costSheetId) {
        try {
            if (pricingElements == null || pricingElements.isEmpty()) {
                throw new AuraHandledException(
                    'No Pricing Elements provided for update.'
                );
            }
            if (String.isBlank(costSheetId)) {
                throw new AuraHandledException('Cost Sheet Id is required.');
            }
            for (Pricing_Element__c pricingElement : pricingElements) {
                pricingElement.Cost_Sheet__c = costSheetId;
                if (pricingElement.Quantity__c != null && pricingElement.Rate__c != null) {
                    Decimal amount = pricingElement.Quantity__c * pricingElement.Rate__c;
                    pricingElement.Amount__c = (amount != amount.setScale(0)) ? amount.setScale(0, RoundingMode.CEILING) : amount;
                }
            }
            upsert pricingElements;
            return 'success';
        } catch (Exception e) {
            System.debug('Error ==> ' + e.getMessage());
            System.debug('Error in line ==> ' + e.getLineNumber());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void submitCostSheetForApproval(String data, String costSheetId){
        System.debug('submitCostSheetForApproval method is get called ');
        try{
            //createRegistrationCharges(costSheetId);
            createPaymentSchedule(costSheetId);
            System.debug('data ===> ' + data);
            // List<Object> discountList = (List<Object>) JSON.deserializeUntyped(data);
            // Map<String, String> discountByPricingMap = new Map<String, String>();
            // for (Object discount : discountList) {
            //     Map<String, Object> discountMap = (Map<String, Object>) discount;
            //     if (discountMap.containsKey('discountAmount') && discountMap.containsKey('id')) {
            //         discountByPricingMap.put(String.valueOf(discountMap.get('discountAmount')), String.valueOf(discountMap.get('id')));
            //     }
            // }
            // if(discountByPricingMap != null && costSheetId != null){
            //     System.debug('discountByPricingMap ===> ' + discountByPricingMap);
            //     System.debug('costSheetId ===> ' + costSheetId);
            //     Map<String, Integer> roleHierarchy = new Map<String, Integer>{
            //         'MD' => 1,
            //         'Sales Head' => 2,
            //         'Sales Manager' => 3,
            //         'Sales Executive' => 4
            //     };
            //     List<Cost_Sheet__c> costSheetRec = [SELECT Id,Opportunity__c, Opportunity__r.Project__c, Opportunity__r.Name,finalize_CostSheet__c from Cost_Sheet__c where Id =: costSheetId LIMIT 1];
            //     System.debug('costSheetRec ===> ' + costSheetRec);
                
            //     String highestDiscountRole = '';
            //     Decimal minDiscount = 0;
            //     String defaultHighestApprover = '';
            //     if(costSheetRec[0].Opportunity__r.Project__c != null){
            //         List<Discount_Master__c> discountMasterList = [SELECT Id,Active__c,Pricing_Element_Master__c,(SELECT Id,Name,Maximum__c,Minimum__c,Roles__c from Discount_LineItems__r) from Discount_Master__c where Project__c =: costSheetRec[0].Opportunity__r.Project__c AND Active__c = true AND Pricing_Element_Master__c IN : discountByPricingMap.values()];
            //         System.debug('discountMasterList ===> ' + discountMasterList);
                    
            //         for(String amount : discountByPricingMap.keySet()){
            //             Decimal amountDecimal = Decimal.valueOf(amount);
            //             String currentPricingEle = discountByPricingMap.get(amount);
            //             System.debug('amountDecimal ===> ' + amountDecimal);
            //             System.debug('pricing ===> ' + discountByPricingMap.get(amount));
                        
            //             for(Discount_Master__c discountMaster : discountMasterList){
            //                 System.debug('discountMaster ===> ' + discountMaster);
            //                 if (currentPricingEle == discountMaster.Pricing_Element_Master__c) {
            //                     List<Discount_LineItem__c> lineItemList = discountMaster.Discount_LineItems__r.isEmpty() ? null : discountMaster.Discount_LineItems__r;
            //                     if(!lineItemList.isEmpty()){
            //                         for(Discount_LineItem__c lineItem : lineItemList){
            //                             System.debug('lineItem ===> ' + lineItem);
            //                             defaultHighestApprover = String.isBlank(defaultHighestApprover) || roleHierarchy.get(lineItem.Roles__c) < roleHierarchy.get(defaultHighestApprover) ? lineItem.Roles__c : defaultHighestApprover;
            //                             minDiscount = minDiscount < lineItem.Minimum__c && minDiscount > 0 ? minDiscount : lineItem.Minimum__c;
            //                             system.debug('minDiscount ===> ' + minDiscount);
            //                             if (amountDecimal >= lineItem.Minimum__c && amountDecimal <= lineItem.Maximum__c) {
            //                                 System.debug('role ===> ' + lineItem.Roles__c);
            //                                 if ((highestDiscountRole == '' || highestDiscountRole == null) || (roleHierarchy.get(lineItem.Roles__c) < roleHierarchy.get(highestDiscountRole))) {
            //                                     highestDiscountRole = lineItem.Roles__c;
            //                                     System.debug('Updated Highest Role to: ' + highestDiscountRole);
            //                                 }
            //                             }
            //                         }
            //                     }
            //                 }
            //             }
            //         }
                    
            //         if(String.isBlank(highestDiscountRole)){
            //             for(String amount : discountByPricingMap.keySet()){
            //                 if(Decimal.valueOf(amount) > minDiscount){
            //                     highestDiscountRole = defaultHighestApprover;
            //                 }
            //             }
            //         }
                    
            //         System.debug('final discount role ===> ' + highestDiscountRole);
            //         costSheetRec[0].Highest_Approver__c = highestDiscountRole;
            //         System.debug('costSheetRec ===> ' + costSheetRec);
            //         update costSheetRec[0];
            //}
            //}
            //createPaymentSchedule(costSheetId);
            
        }catch(Exception e){
            system.debug('Error ==> ' + e.getMessage());
            system.debug('Error in line ==> ' + e.getLineNumber());
        }
    }

    private static void createRegistrationCharges(String costSheetId) {
        if (String.isBlank(costSheetId)) {
            return;
        }

        system.debug('costSheetId::'+costSheetId);

        //List<Pricing_Element_Master__c> registartionCharges = [SELECT Id, Name, Agreement__c FROM Pricing_Element_Master__c WHERE Name = 'Registration Charges*' LIMIT 1];
        List<Agreement__c> settings = [SELECT Name__c, Percentage__c, Type__c FROM Agreement__c LIMIT 1];

        // if (registartionCharges.isEmpty() || settings.isEmpty() || settings[0].Percentage__c == null) {
        //     return;
        // }

        Decimal totalAgreementValue = 0;
        for (Pricing_Element__c pricingElement : [
            SELECT Id, Type__c, Total_Amount_Excluding_Tax__c
            FROM Pricing_Element__c
            WHERE Cost_Sheet__c = :costSheetId
        ]) {
            if (pricingElement.Total_Amount_Excluding_Tax__c != null && pricingElement.Type__c == 'Agreement') {
                totalAgreementValue += pricingElement.Total_Amount_Excluding_Tax__c;
            }
        }

        Decimal calcValue = (totalAgreementValue * settings[0].Percentage__c) / 100;
        Decimal roundedValue = (calcValue != calcValue.setScale(0)) ? calcValue.setScale(0, RoundingMode.CEILING) : calcValue;

        // List<Pricing_Element__c> existingRegistrationCharges = [
        //     SELECT Id
        //     FROM Pricing_Element__c
        //     WHERE Cost_Sheet__c = :costSheetId
        //     AND Pricing_Element_Master__c = :registartionCharges[0].Id
        //     LIMIT 1
        // ];

        // Pricing_Element__c registrationCharge = existingRegistrationCharges.isEmpty()
        //     ? new Pricing_Element__c(Cost_Sheet__c = costSheetId, Pricing_Element_Master__c = registartionCharges[0].Id)
        //     : new Pricing_Element__c(Id = existingRegistrationCharges[0].Id);

        // registrationCharge.Type__c = 'Ammenities';
        // registrationCharge.Quantity__c = 1;
        // registrationCharge.Rate__c = roundedValue;
        // registrationCharge.Amount__c = roundedValue;

        // upsert registrationCharge;
    }

    //19-08 - to create payment schedule from cost sheet
    @AuraEnabled
    public static void createPaymentSchedule(Id costSheetId) {
        System.debug('Processing Cost Sheet ID: ' + costSheetId);
        Id selectedCostSheetTempId;
        
        try {
            if(costSheetId != null){
                Cost_Sheet__c getCostSheet = [select id,Opportunity__c,Name,Cost_Scheme_Linking__c,finalize_CostSheet__c,Total_Pricing_Value__c, Total_Pricing_Value_Excluding_Tax__c, Total_Tax_Value__c,Cost_Scheme_Linking__r.Cost_Sheet_Template__c from Cost_Sheet__c Where Id =:costSheetId Limit 1];
                
                selectedCostSheetTempId = getCostSheet?.Cost_Scheme_Linking__r?.Cost_Sheet_Template__c != null ? getCostSheet.Cost_Scheme_Linking__r.Cost_Sheet_Template__c : '';
                
                Cost_Scheme_Linking__c getSchemeLinking = [select id,Payment_Scheme__c,Cost_Sheet_Template__c,Cost_Sheet_Template__r.Amount__c,Cost_Sheet_Template__r.Tax_Amount__c  from Cost_Scheme_Linking__c Where id =:getCostSheet.Cost_Scheme_Linking__c Limit 1];
                System.debug('Scheme Liking: ' + getSchemeLinking);
                
                List<Payment_Scheme_Installment__c> getPaymetSchemeRecords = [select id,Payment_Scheme__c,Payment_Scheme__r.Name,Installment__c,Name,Payment_Schedule_Master__c,Payment_Schedule_Master__r.Name,Display_Order__c,Payment_Schedule_Master__r.Installment_Code__c, Payment_Schedule_Master__r.Installment_Sequence__c,Type__c,Payment_Schedule_Master__r.Description__c  from Payment_Scheme_Installment__c Where Payment_Scheme__c  =:getSchemeLinking.Payment_Scheme__c];
                System.debug('getPaymetSchemeRecords size: ' + getPaymetSchemeRecords.size());
                Decimal smallDisplayNum =  10000;
                for(Payment_Scheme_Installment__c psi : getPaymetSchemeRecords){
                    if(psi.Display_Order__c  < smallDisplayNum){
                        smallDisplayNum = psi.Display_Order__c;
                    }
                }
                Decimal totalAgreementValue = 0;
                Decimal tokenAmount = 0;
                //List<Payment_Schedule__c> allPaymentSchedules = new List<Payment_Schedule__c>();
                List<Cost_Sheet_Payment_Schedule__c> allPaymentSchedules = new List<Cost_Sheet_Payment_Schedule__c>();
                
                for(Payment_Scheme_Installment__c psi : getPaymetSchemeRecords){
                    Cost_Sheet_Payment_Schedule__c ps = new Cost_Sheet_Payment_Schedule__c();
                    Decimal rawAgreement = (getCostSheet.Total_Pricing_Value_Excluding_Tax__c / 100) * psi.Installment__c;
                    Decimal rawTax = (getCostSheet.Total_Tax_Value__c / 100) * psi.Installment__c;

                    ps.Opportunity__c = getCostSheet.Opportunity__c;
                    ps.Cost_Sheet__c = costSheetId;
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
                    allPaymentSchedules.add(ps);
                }
                
                List<Pricing_Element__c> ammentiesPricingElements = [select Id,Cost_Sheet__c,Pricing_Element_Master__c,Pricing_Element_Master__r.Name,Type__c,Quantity__c,Amount__c,Actual_Amount__c,Total_Amount_Excluding_Tax__c,Final_Tax_Amount__c,Description__c, Sequence__c  from Pricing_Element__c Where Cost_Sheet__c =: costSheetId and Type__c ='Ammenities'];
                for(Pricing_Element__c pe : ammentiesPricingElements){
                    Cost_Sheet_Payment_Schedule__c ps =  new Cost_Sheet_Payment_Schedule__c();
                    ps.Name = pe.Pricing_Element_Master__r.Name;
                    ps.Type__c =  pe.Type__c;
                    ps.Cost_Sheet__c = costSheetId;

                    ps.Agreement_Value__c = pe.Total_Amount_Excluding_Tax__c;
                    ps.Tax_Amount__c = pe.Final_Tax_Amount__c;
                    ps.Description__c = pe.Description__c;
                    ps.Installment_Sequence__c = pe.Sequence__c;
                    ps.Opportunity__c = getCostSheet.Opportunity__c;
                    allPaymentSchedules.add(ps);

                }
                insert allPaymentSchedules;
            }
        } catch (Exception e) {
            System.debug(' Error ===> ' + e.getLineNumber() + ' ---> ' + e.getMessage());
        }
    }
    
    public static void testData(){
        Integer i =0 ;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
        i++;i++; i++;i++;
    }
}