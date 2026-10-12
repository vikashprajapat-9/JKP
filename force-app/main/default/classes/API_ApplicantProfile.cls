@RestResource(urlMapping='/api/v1/applicants/profile')
global without sharing class API_ApplicantProfile {

    private static final List<String> ORDINAL_WORDS = new List<String>{
        'First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth', 'Ninth', 'Tenth'
    };

    @HttpGet
    global static void getApplicantProfile() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            ApplicantProfileResponse result = buildApplicantProfileResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_ApplicantProfile.getApplicantProfile ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ApplicantProfile', 'getApplicantProfile', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving applicant profile', null)));
        }
    }

    private static ApplicantProfileResponse buildApplicantProfileResponse(RestRequest request) {
        try {
            String applicantId = request != null && request.params != null ? request.params.get('applicantId') : null;
            applicantId = applicantId != null ? applicantId.trim() : null;

            if (String.isBlank(applicantId)) {
                return createResponse(false, 400, 'applicantId is required', null);
            }

            return getApplicantProfileData(applicantId);
        } catch (Exception e) {
            System.debug('Error in API_ApplicantProfile.buildApplicantProfileResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ApplicantProfile', 'buildApplicantProfileResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving applicant profile', null);
        }
    }

    private static ApplicantProfileResponse getApplicantProfileData(String applicantId) {
        List<Applicant__c> matchedApplicants = [
            SELECT Id, Name, CreatedDate, IsPrimary__c, Opportunity__c,Account__c, Account__r.Name, Account__r.Phone, Account__r.Email__c,
                   Account__r.ShippingStreet, Account__r.ShippingCity, Account__r.ShippingState,Account__r.ShippingPostalCode, Account__r.ShippingCountry,
                   Account__r.BillingStreet, Account__r.BillingCity, Account__r.BillingState,Account__r.BillingPostalCode, Account__r.BillingCountry,
                   Account__r.TIN_Tax_Identification_Number__c, Account__r.Passport__c
            FROM Applicant__c
            WHERE Name = :applicantId WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (matchedApplicants.isEmpty()) {
            return createResponse(false, 404, 'Applicant not found', null);
        }
        Applicant__c applicant = matchedApplicants[0];

        Integer applicantPosition = 1;
        if (applicant.Opportunity__c != null) {
            List<Applicant__c> siblingApplicants = [SELECT Id, CreatedDate FROM Applicant__c WHERE Opportunity__c = :applicant.Opportunity__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC];
            for (Integer index = 0; index < siblingApplicants.size(); index++) {
                if (siblingApplicants[index].Id == applicant.Id) {
                    applicantPosition = index + 1;
                    break;
                }
            }
        }

        String salutation = null;
        if (applicant.Account__c != null) {
            List<Contact> accountContacts = [SELECT Id, Salutation FROM Contact WHERE AccountId = :applicant.Account__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
            salutation = accountContacts.isEmpty() ? null : accountContacts[0].Salutation;
        }

        KycDetailsWrapper kycDetails = new KycDetailsWrapper();
        kycDetails.mobileNumber   = applicant.Account__c != null ? applicant.Account__r.Phone : null;
        kycDetails.emailId        = applicant.Account__c != null ? applicant.Account__r.Email__c : null;
        kycDetails.address        = applicant.Account__c != null ? buildAddress(applicant.Account__r) : null;
       // kycDetails.nicNumber      = null;
        kycDetails.tinNumber      = applicant.Account__c != null ? applicant.Account__r.TIN_Tax_Identification_Number__c : null;
        kycDetails.passportNumber = applicant.Account__c != null ? applicant.Account__r.Passport__c : null;

        ApplicantProfileData profileData = new ApplicantProfileData();
        profileData.applicantId   = applicant.Name;
        profileData.salutation    = salutation;
        profileData.fullName      = applicant.Account__c != null ? applicant.Account__r.Name : null;
        profileData.applicantType = buildApplicantType(applicantPosition);
        profileData.kycDetails    = kycDetails;

        return createResponse(true, 200, 'Applicant profile retrieved successfully', profileData);
    }

    private static String buildAddress(Account account) {
        Boolean hasShippingAddress = String.isNotBlank(account.ShippingStreet)|| String.isNotBlank(account.ShippingCity)|| String.isNotBlank(account.ShippingState)|| String.isNotBlank(account.ShippingPostalCode)|| String.isNotBlank(account.ShippingCountry);

        List<String> addressParts = hasShippingAddress
            ? new List<String>{ account.ShippingStreet, account.ShippingCity, account.ShippingState, account.ShippingPostalCode, account.ShippingCountry }
            : new List<String>{ account.BillingStreet, account.BillingCity, account.BillingState, account.BillingPostalCode, account.BillingCountry };

        List<String> nonBlankParts = new List<String>();
        for (String addressPart : addressParts) {
            if (String.isNotBlank(addressPart)) {
                nonBlankParts.add(addressPart);
            }
        }
        return nonBlankParts.isEmpty() ? null : String.join(nonBlankParts, ', ');
    }

    private static String buildApplicantType(Integer position) {
        String ordinalWord = position >= 1 && position <= ORDINAL_WORDS.size()? ORDINAL_WORDS[position - 1]: position + numericSuffix(position);
        return ordinalWord + ' Applicant';
    }

    private static String numericSuffix(Integer position) {
        Integer lastTwoDigits = Math.mod(position, 100);
        Integer lastDigit     = Math.mod(position, 10);
        return (lastTwoDigits >= 11 && lastTwoDigits <= 13) ? 'th'
            : lastDigit == 1 ? 'st'
            : lastDigit == 2 ? 'nd'
            : lastDigit == 3 ? 'rd'
            : 'th';
    }

    private static ApplicantProfileResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, ApplicantProfileData data) {
        ApplicantProfileResponse apiResponse = new ApplicantProfileResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class ApplicantProfileResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public ApplicantProfileData data;
    }

    public class ApplicantProfileData {
        public String applicantId;
        public String salutation;
        public String fullName;
        public String applicantType;
        public KycDetailsWrapper kycDetails;
    }

    public class KycDetailsWrapper {
        public String mobileNumber;
        public String emailId;
        public String address;
        public String nicNumber;
        public String tinNumber;
        public String passportNumber;
    }
}