@RestResource(urlMapping='/api/v1/create-referrals')
global without sharing class API_CreateReferral {

    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[\\w.+-]+@[\\w-]+\\.[a-zA-Z]{2,}$');

    @HttpPost
    global static void createReferral() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            CreateReferralResponse result = createReferralLead(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_CreateReferral.createReferral ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_CreateReferral', 'createReferral', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, e.getMessage(), null)));
        }
    }

    private static CreateReferralResponse createReferralLead(RestRequest request) {
        try {
            RequestWrapper referralRequest;
            try {
                referralRequest = (RequestWrapper) JSON.deserialize(request.requestBody.toString(), RequestWrapper.class);
            } catch (Exception ex) {
                return createResponse(false, 400, 'Invalid request body', null);
            }

            if (referralRequest == null) {
                return createResponse(false, 400, 'Required fields are missing', null);
            }

            String userId = referralRequest.userId;
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'userId is required', null);
            }
            userId = userId.trim();
            if (!isValidSalesforceId(userId)) {
                return createResponse(false, 400, 'Invalid userId', null);
            }

            if (String.isBlank(referralRequest.propertyId) || !isValidSalesforceId(referralRequest.propertyId.trim())) {
                return createResponse(false, 400, 'propertyId is required and must be a valid Id', null);
            }
            Id propertyId = Id.valueOf(referralRequest.propertyId.trim());

            if (String.isBlank(referralRequest.fullName)) {
                return createResponse(false, 400, 'fullName is required', null);
            }
            String fullName = referralRequest.fullName.trim();

            if (String.isBlank(referralRequest.email) || !EMAIL_PATTERN.matcher(referralRequest.email.trim()).matches()) {
                return createResponse(false, 400, 'A valid email is required', null);
            }
            String email = referralRequest.email.trim();

            if (String.isBlank(referralRequest.countryCode) || String.isBlank(referralRequest.phone)) {
                return createResponse(false, 400, 'countryCode and phone are required', null);
            }
            String fullPhone = referralRequest.countryCode.trim() + referralRequest.phone.trim();

            // if (String.isBlank(referralRequest.budgetAligned)) {
            //     return createResponse(false, 400, 'budgetAligned is required', null);
            // }
            // String budgetAligned = referralRequest.budgetAligned.trim();

            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
            if (matchedUsers.isEmpty()) {
                return createResponse(false, 404, 'User not found', null);
            }
            Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;
            if (accountId == null) {
                return createResponse(false, 400, 'User is not associated with an account', null);
            }

            List<Project__c> matchedProjects = [SELECT Id, Name FROM Project__c WHERE Id = :propertyId WITH SYSTEM_MODE LIMIT 1];
            if (matchedProjects.isEmpty()) {
                return createResponse(false, 404, 'Property not found', null);
            }
            Project__c project = matchedProjects[0];

            Lead newLead = new Lead();
            newLead.LastName     = fullName;
            newLead.Email        = email;
            newLead.Phone        = fullPhone;
            newLead.Project__c   = project.Id;
            newLead.Referred_By__c = accountId;
          //  newLead.Budget_Aligned__c = budgetAligned;
            newLead.LeadSource = 'Referral';
            newLead.Lead_Sub_Source__c = 'Referral';
            newLead.Company = fullName;

            try {
                Database.insert(newLead, AccessLevel.SYSTEM_MODE);
            } catch (DmlException dmlEx) {
                System.debug('DML error in API_CreateReferral.createReferralLead ===> ' + dmlEx.getMessage());
                IntegrationLogUtility.captureError('API_CreateReferral', 'createReferralLead', dmlEx, null, 'SFA - SFDC');
                return createResponse(false, 500, dmlEx.getDmlMessage(0), null);
            }

            Lead insertedLead = [SELECT Id, Name, Email, Phone, Status, Project__c, CreatedDate, Budget_Aligned__c FROM Lead WHERE Id = :newLead.Id WITH SYSTEM_MODE LIMIT 1];

            Map<String, String> statusLabelByApiValue = getLeadStatusLabels();

            ResponseDataWrapper data = new ResponseDataWrapper();
            data.referralId          = String.valueOf(insertedLead.Id);
            data.fullName            = insertedLead.Name;
            data.propertyName        = project.Name;
            data.propertyId          = String.valueOf(project.Id);
            data.email               = insertedLead.Email;
            data.phone               = insertedLead.Phone;
         //   data.budgetAligned       = insertedLead.Budget_Aligned__c;
            data.status              = insertedLead.Status;
            data.statusLabel         = insertedLead.Status != null && statusLabelByApiValue.containsKey(insertedLead.Status) ? statusLabelByApiValue.get(insertedLead.Status) : insertedLead.Status;

            return createResponse(true, 201, 'Referral submitted successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_CreateReferral.createReferralLead ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_CreateReferral', 'createReferralLead', e, null, 'SFA - SFDC');
            return createResponse(false, 500, e.getMessage(), null);
        }
    }

    private static Map<String, String> getLeadStatusLabels() {
        Map<String, String> statusLabelByApiValue = new Map<String, String>();
        for (Schema.PicklistEntry entry : Lead.Status.getDescribe().getPicklistValues()) {
            statusLabelByApiValue.put(entry.getValue(), entry.getLabel());
        }
        return statusLabelByApiValue;
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static CreateReferralResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ResponseDataWrapper data) {
        CreateReferralResponse apiResponse = new CreateReferralResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class RequestWrapper {
        public String userId;
        public String propertyId;
        public String fullName;
        public String email;
        public String countryCode;
        public String phone;
    //    public String budgetAligned;
    }

    public class CreateReferralResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ResponseDataWrapper data;
    }

    public class ResponseDataWrapper {
        public String referralId;
        public String fullName;
        public String propertyName;
        public String propertyId;
        public String email;
        public String phone;
        public String status;
        public String statusLabel;
     //   public String budgetAligned;
    }
}