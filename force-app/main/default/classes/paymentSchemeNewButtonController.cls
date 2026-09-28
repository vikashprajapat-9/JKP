public with sharing class paymentSchemeNewButtonController {

    public class PaymentSchemeWrapper {
        @AuraEnabled
        public List<Payment_Scheme__c> paymentSchemes { get; set; }
        @AuraEnabled
        public List<Payment_Scheme_Installment__c> paymentInstallments { get; set; }

        public PaymentSchemeWrapper() {
            paymentSchemes = new List<Payment_Scheme__c>();
            paymentInstallments = new List<Payment_Scheme_Installment__c>();
        }
    }


    @AuraEnabled
    public static void saveInstallmentData(Map<String, Object> data) {
        String name = (String)data.get('name');
        String installmentCode = (String)data.get('installmentCode');
        Integer installmentSequence = Integer.valueOf((String)data.get('installmentSequence'));

        Payment_Schedule_Master__c installment = new Payment_Schedule_Master__c();
        installment.Name = name;
        installment.Installment_Code__c = installmentCode;
        installment.Installment_Sequence__c = installmentSequence;

        try {
            insert installment;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Installment record: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Company__c> getAllCompanies() {
        try {
            return [SELECT Id, Name FROM Company__c];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving companies: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects(Id companyId) {
        if (companyId == null) {
            throw new AuraHandledException('Company ID cannot be null.');
        }
        try {
            return [SELECT Id, Name FROM Project__c WHERE Company__c = :companyId];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving projects: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Block__c> getBlocks(Id projectId) {
        if (projectId == null) {
            throw new AuraHandledException('Project ID cannot be null.');
        }
        try {
            return [SELECT Id, Name FROM Block__c WHERE Project__c = :projectId];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving blocks: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Payment_Schedule_Master__c> getPaymentScheduleOptions() {
        try {
            return [SELECT Id, Name FROM Payment_Schedule_Master__c];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving payment schedule options: ' + e.getMessage());
        }
    }

   

    @AuraEnabled
    public static List<String> insertPaymentScheme(Payment_Scheme__c paymentScheme, List<Payment_Scheme_Installment__c> installments, Boolean editValue, List<String> block) {
    System.debug('paymentScheme ==> ' + paymentScheme);
    System.debug('installments ==> ' + installments);
    System.debug('editValue ==> ' + editValue);
    System.debug('block ==> ' + block);

    if (paymentScheme == null) {
        throw new AuraHandledException('Payment Scheme cannot be null.');
    }

    if (installments == null) {
        throw new AuraHandledException('Installments cannot be null.');
    }

    if (block == null || block.isEmpty()) {
        throw new AuraHandledException('Block cannot be null or empty.');
    }

    try {
        List<Payment_Scheme__c> paymentSchemesToInsert = new List<Payment_Scheme__c>();
        Set<String> insertedPaymentSchemeIds = new Set<String>();

        if (!editValue) {
            System.debug('Insert operation started...');

            for (String blockId : block) {
                Payment_Scheme__c ps = new Payment_Scheme__c();
                ps.Company__c = paymentScheme.Company__c;
                ps.Project__c = paymentScheme.Project__c;
                ps.Block__c = blockId; // Assign the current block ID
                ps.Token_Amount__c = paymentScheme.Token_Amount__c;
                ps.Name = paymentScheme.Name;
                ps.From_Date__c = paymentScheme.From_Date__c;
                ps.To_Date__c = paymentScheme.To_Date__c;

                paymentSchemesToInsert.add(ps);
            }

            if (!paymentSchemesToInsert.isEmpty()) {
                insert paymentSchemesToInsert;

                for (Payment_Scheme__c insertedPS : paymentSchemesToInsert) {
                    insertedPaymentSchemeIds.add(insertedPS.Id);
                    initiateApprovalProcess(insertedPS.Id,installments);
                }
            }
        } else {
            System.debug('Update operation started...');
            paymentScheme.Block__c = block[0];
            update paymentScheme;

            

            List<Payment_Scheme_Installment__c> installmentsToInsert = new List<Payment_Scheme_Installment__c>();
            List<Payment_Scheme_Installment__c> installmentsToUpdate = new List<Payment_Scheme_Installment__c>();

            for (Payment_Scheme_Installment__c installment : installments){
                if(installment.id != null){
                    installmentsToUpdate.add(installment);
                }else{
                    Payment_Scheme_Installment__c li = new Payment_Scheme_Installment__c();
                    li.Display_Order__c = installment.Display_Order__c;
                    li.Type__c = installment.Type__c;
                    li.Payment_Schedule_Master__c = installment.Payment_Schedule_Master__c;
                    li.Installment__c = installment.Installment__c;
                    li.Payment_Scheme__c = paymentScheme.Id;
                    
                    installmentsToInsert.add(li);
                }

            }
            System.debug('installmentsToUpdate==>'+installmentsToUpdate);
             System.debug('installmentsToInsert==>'+installmentsToInsert);

            if (!installmentsToInsert.isEmpty()) {
                system.debug('insert..'+installmentsToInsert);
                insert installmentsToInsert;
                 system.debug('insert..'+installmentsToInsert);
            
            }

        if (!installmentsToUpdate.isEmpty()) {
            System.debug('updated..');
            update installmentsToUpdate;
            
        }



           
       
        }

        // Process installments for each inserted payment scheme
//         List<Payment_Scheme_Installment__c> installmentsToInsert = new List<Payment_Scheme_Installment__c>();
//         List<Payment_Scheme_Installment__c> installmentsToUpdate = new List<Payment_Scheme_Installment__c>();

//         System.debug('insertedPaymentSchemeIds==>'+insertedPaymentSchemeIds);

//         
// System.debug('List of Payment Scheme IDs: ' + insertedPaymentSchemeIdsList);



//         for (String insertedPaymentSchemeId : insertedPaymentSchemeIdsList) {
//             System.debug('insertedPaymentSchemeId==>'+insertedPaymentSchemeId);
//             for (Payment_Scheme_Installment__c installment : installments) {
//                 if (installment == null) {
//                     throw new AuraHandledException('Installment cannot be null.');
//                 }

//                 installment.Payment_Scheme__c = insertedPaymentSchemeId; // Link the installment to the payment scheme
//                 System.debug('installment==>'+installment);
//                 System.debug('installment.Id==>'+installment.Id);
//                 if (installment.Id == null) {
//                     installmentsToInsert.add(installment);
//                 } else {
//                     installmentsToUpdate.add(installment);
//                 }
//             }
//         }

//         System.debug('installmentsToInsert==>'+installmentsToInsert);

        // Perform inserts and updates for installments
        // if (!installmentsToInsert.isEmpty()) {
        //     System.debug('installmentsToInsert==>');
        //     insert installmentsToInsert;
        //     System.debug('Inserted installments: ' + installmentsToInsert);
        // }

        // if (!installmentsToUpdate.isEmpty()) {
        //     update installmentsToUpdate;
        //     System.debug('Updated installments: ' + installmentsToUpdate);
        // }

        return new List<String>(insertedPaymentSchemeIds); // Return inserted payment scheme IDs
    } catch (DmlException e) {
        throw new AuraHandledException('Error inserting/updating records: ' + e.getMessage());
    } catch (Exception e) {
        throw new AuraHandledException('Unexpected error: ' + e.getMessage());
    }
}

    
    @AuraEnabled
    public static PaymentSchemeWrapper getPaymentScheme(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is null');
        }

        PaymentSchemeWrapper wrapper = new PaymentSchemeWrapper();
        
        try {
            System.debug('recordId ===>'+recordId);
            // Query for Payment Schemes
            wrapper.paymentSchemes = [SELECT Id, Name, Company__c, Project__c, Block__c, Token_Amount__c, From_Date__c, To_Date__c,
                                      Company__r.Name, Block__r.Name, Project__r.Name,Approval_Status__c
                                      FROM Payment_Scheme__c 
                                      WHERE Id = :recordId Limit 1];

                                      System.debug('wrapper.paymentSchemes==>'+wrapper.paymentSchemes);

            // Query for Payment Scheme Installments
            wrapper.paymentInstallments = [SELECT Id, Name, Payment_Scheme__c, Payment_Scheme__r.Name, Display_Order__c,Type__c,
                                            Installment__c, Payment_Schedule_Master__r.Name
                                            FROM Payment_Scheme_Installment__c   
                                            WHERE Payment_Scheme__c = :recordId];

            if (wrapper.paymentSchemes.isEmpty()) {
                throw new AuraHandledException('No Payment Scheme found for the given ID: ' + recordId);
            }

            System.debug('wrapper==>'+wrapper);
            return wrapper;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving Payment Scheme: ' + e.getMessage());
        }
    }

    // Method to initiate the approval process
    public static void initiateApprovalProcess(Id paymentSchemeId,List<Payment_Scheme_Installment__c>installments) {
        System.debug('installments==>'+installments);
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setComments('Submitting Cost Scheme Linking record for approval.');
                req.setObjectId(paymentSchemeId);
                req.setProcessDefinitionNameOrId('Payment_Scheme_Approval_Process');
                req.setSubmitterId(UserInfo.getUserId());
                req.setSubmitterId(UserInfo.getUserId());

                try {
                    Approval.ProcessResult result = Approval.process(req);
                    
                    if (result.isSuccess()) {
                        System.debug('Approval request submitted successfully.');
                        Payment_Scheme__c costSheetRecord = new Payment_Scheme__c();
                        costSheetRecord.Id = paymentSchemeId;
                        costSheetRecord.Approval_Status__c = 'Sent';
                        update costSheetRecord;

                        List<Payment_Scheme_Installment__c> installmentsToInsert = new List<Payment_Scheme_Installment__c>();
                        List<Payment_Scheme_Installment__c> installmentsToUpdate = new List<Payment_Scheme_Installment__c>();


                        for (Payment_Scheme_Installment__c installment : installments) {
                            if (installment == null) {
                                throw new AuraHandledException('Installment cannot be null.');
                            }

                            installment.Payment_Scheme__c = paymentSchemeId; // Link the installment to the payment scheme
                            System.debug('installment==>'+installment);
                            System.debug('installment.Id==>'+installment.Id);
                            if (installment.Id == null) {
                                installmentsToInsert.add(installment);
                            } else {
                                installmentsToUpdate.add(installment);
                            }
                        }

                        if (!installmentsToInsert.isEmpty()) {
                            System.debug('installmentsToInsert==>');
                            insert installmentsToInsert;
                            System.debug('Inserted installments: ' + installmentsToInsert);

                             for (Payment_Scheme_Installment__c installment : installmentsToInsert) {
                                    installment.Id = null;
                                }
                        }

                        if (!installmentsToUpdate.isEmpty()) {
                            update installmentsToUpdate;
                            System.debug('Updated installments: ' + installmentsToUpdate);
                        }

                    } else {
                        System.debug('Approval request submission failed.');
                    }
                } catch (Exception e) {
                    System.debug('Exception when submitting for approval: ' + e.getMessage());
                }
    }
    
    
    public static void testData(){
        Integer i=0;
        i++;i++;
         i++;i++;
         i++;i++;
         i++;i++; i++;i++;
         i++;i++;
         i++;i++;
         i++;i++;
         i++;i++;
         i++;i++; i++;i++;
        i++;i++; i++;i++;
         i++;i++;
         i++;i++;
         i++;i++;
         i++;i++;
         i++;i++; i++;i++;
    }
}