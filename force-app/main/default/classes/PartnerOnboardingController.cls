public with sharing class PartnerOnboardingController {
    //  LWC DESERIALIZATION
    public class RegistrationRequest {
        @AuraEnabled public String registrationType { get; set; }
        @AuraEnabled public String businessName     { get; set; }
        @AuraEnabled public String vatNumber        { get; set; }
        @AuraEnabled public String nameAsPerNic     { get; set; }
        @AuraEnabled public String homeAddress      { get; set; }
        @AuraEnabled public String nicNumber        { get; set; }
        @AuraEnabled public String passport         { get; set; }
        @AuraEnabled public String tin              { get; set; }
        @AuraEnabled public String email            { get; set; }
        @AuraEnabled public String phone            { get; set; }
        @AuraEnabled public String projectId        { get; set; }
        @AuraEnabled public String fileName         { get; set; }
        @AuraEnabled public String fileBase64       { get; set; }
        public RegistrationRequest() {}
    }

    @AuraEnabled
    public static Id submitRegistration(RegistrationRequest req) {

        System.debug('>>> [PartnerOnboarding] Received Payload: ' + JSON.serialize(req));

        if (req == null) {
            System.debug('>>> [PartnerOnboarding] ERROR: req object is NULL.');
            throw createHandledException('Request payload was empty. Please check form data.');
        }

        // 1. NULL-SAFE EXTRACTIONS
        String cleanPhone = safeTrim(req.phone);
        String cleanEmail = safeTrim(req.email);
        String regType    = String.isNotBlank(req.registrationType) ? req.registrationType.trim() : 'Company';

        System.debug('PartnerOnboarding] Registration Type: ' + regType);
  

        // 2. MANDATORY VALIDATIONS
        if (String.isBlank(cleanPhone)) {
            System.debug('PartnerOnboarding] Validation Failed: Phone is blank');
            throw createHandledException('Phone number is required.');
        }
        if (String.isBlank(cleanEmail)) {
            System.debug('PartnerOnboarding] Validation Failed: Email is blank');
            throw createHandledException('Email address is required.');
        }

        // 3. DUPLICATE CHECK BY PHONE
        List<Account> existingAccounts = [
            SELECT Id, Name, Phone 
            FROM Account 
            WHERE Phone = :cleanPhone 
            LIMIT 1
        ];

        if (!existingAccounts.isEmpty()) {
            System.debug('PartnerOnboarding Duplicate Phone Found! Account Id: ' + existingAccounts[0].Id);
            throw createHandledException('A partner with this phone number is already registered.');
        }

        // 4. RECORD TYPE RESOLUTION
        Account partner = new Account();
        Id resolvedRecordTypeId = getRecordTypeIdSafely(regType);
        if (resolvedRecordTypeId != null) {
            partner.RecordTypeId = resolvedRecordTypeId;
            System.debug('PartnerOnboarding] Assigned RecordTypeId: ' + resolvedRecordTypeId);
        }

        // 5. MAP FIELDS
        if (regType == 'Individual') {
            String cleanNameAsPerNic = safeTrim(req.nameAsPerNic);
            if (String.isBlank(cleanNameAsPerNic)) {
                throw createHandledException('Name as per NIC is required.');
            }

            partner.Name = cleanNameAsPerNic;

            if (String.isNotBlank(req.homeAddress)) {
                partner.BillingStreet = safeTrim(req.homeAddress);
            }

        } else {
            // Company
            String cleanBusinessName = safeTrim(req.businessName);
            if (String.isBlank(cleanBusinessName)) {
                throw createHandledException('Business name is required.');
            }

            partner.Name             = cleanBusinessName;
            //partner.Business_Name__c = cleanBusinessName;
            partner.VAT_Number__c    = safeTrim(req.vatNumber);
             
        }

        // Common Fields
        partner.TIN_Tax_Identification_Number__c = safeTrim(req.tin);
        partner.Email__c                         = cleanEmail;
        partner.Phone                            = cleanPhone;
        partner.Portal_Registration_User__c=true;
        partner.Onboarding_Status__c ='Pending';

        if (String.isNotBlank(req.projectId)) {
            try {
                partner.Project__c = (Id) safeTrim(req.projectId);
            } catch (Exception e) {
                System.debug('PartnerOnboarding] Invalid Project Id: ' + req.projectId);
            }
        }
     insert partner;
             try {
            Approval.ProcessSubmitRequest reqApproval = new Approval.ProcessSubmitRequest();
            reqApproval.setComments('Submitted automatically from Channel Partner Registration Form.');
            reqApproval.setObjectId(partner.Id);
            reqApproval.setProcessDefinitionNameOrId('Partner_Onboarding_Approval');
            Approval.ProcessResult result = Approval.process(reqApproval);
            
            System.debug('PartnerOnboarding] Account Created! Id: ' + partner.Id);
            System.debug('>>> [PartnerOnboarding] Auto-approval submitted? ' + result.isSuccess());
        } catch (DmlException e) {
            System.debug('PartnerOnboarding] DmlException: ' + e.getDmlMessage(0));
            throw createHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            System.debug('PartnerOnboarding] Exception: ' + e.getMessage());
            throw createHandledException(e.getMessage());
        }
            // create contact once account is inserted
            list<Contact> conList=new list<Contact>();
            contact con=new contact();
            con.AccountId=partner.Id;
            con.LastName=partner.Name;
            con.Email=partner.Email__c;
            con.Phone=partner.Phone; 
            con.MailingStreet     = partner.BillingStreet;
            con.MailingCity       = partner.BillingCity;
            con.MailingState      = partner.BillingState;
            con.MailingPostalCode = partner.BillingPostalCode;
            con.MailingCountry    = partner.BillingCountry;
            insert con;
            conList.add(con);

        // 7. FILE UPLOAD
        if (String.isNotBlank(req.fileBase64) && String.isNotBlank(req.fileName)) {
            saveFile(req.fileBase64, req.fileName, partner.Id);
        }

        return partner.Id;
    }

    private static Id getRecordTypeIdSafely(String typeName) {
        if (String.isBlank(typeName)) return null;

        Map<String, Schema.RecordTypeInfo> byDevName = 
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        if (byDevName.containsKey(typeName) && byDevName.get(typeName).isActive()) {
            return byDevName.get(typeName).getRecordTypeId();
        }

        Map<String, Schema.RecordTypeInfo> byName = 
            Schema.SObjectType.Account.getRecordTypeInfosByName();
        if (byName.containsKey(typeName) && byName.get(typeName).isActive()) {
            return byName.get(typeName).getRecordTypeId();
        }

        return null;
    }

    private static String safeTrim(String str) {
        return (str != null) ? str.trim() : null;
    }

    private static void saveFile(String base64Data, String fileName, Id accountId) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title          = fileName;
            cv.PathOnClient   = fileName;
            cv.VersionData    = EncodingUtil.base64Decode(base64Data);
            cv.IsMajorVersion = true;
            insert cv;

            cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            ContentDocumentLink link = new ContentDocumentLink();
            link.ContentDocumentId   = cv.ContentDocumentId;
            link.LinkedEntityId      = accountId;
            link.ShareType           = 'V';
            link.Visibility          = 'AllUsers';
            insert link;
            System.debug('>>> [PartnerOnboarding] File linked to Account: ' + accountId);

        } catch (Exception e) {
            System.debug('>>> [PartnerOnboarding] File upload error: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ProjectOption> getProjectOptions() {
        List<ProjectOption> opts = new List<ProjectOption>();
        for (Project__c p : [SELECT Id, Name FROM Project__c WHERE Active__c = true ORDER BY Name LIMIT 200]) {
            opts.add(new ProjectOption(p.Id, p.Name));
        }
        return opts;
    }

    public class ProjectOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public ProjectOption(Id id, String name) {
            this.value = id;
            this.label = name;
        }
    }

    private static AuraHandledException createHandledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}