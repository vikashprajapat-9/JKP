@RestResource(urlMapping='/api/v1/lets_talk/*')
global without sharing class API_LetsTalk {

    @HttpGet
    global static void getLetsTalk() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            LetsTalkResponse result = buildLetsTalkResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_LetsTalk.getLetsTalk ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_LetsTalk', 'getLetsTalk', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving contact details', null)));
        }
    }

    private static LetsTalkResponse buildLetsTalkResponse(RestRequest request) {
        try {
            Map<String, String> params = request != null && request.params != null ? request.params : new Map<String, String>();

            String userId = UserInfo.getUserId();
            if (String.isBlank(userId)) {
                return createResponse(false, 400, 'userId is required', null);
            }
            userId = userId.trim();
            if (!isValidSalesforceId(userId)) {
                return createResponse(false, 400, 'Invalid userId', null);
            }

            String propertyId = params.get('propertyId');
            if (String.isBlank(propertyId)) {
                return createResponse(false, 400, 'propertyId is required', null);
            }
            propertyId = propertyId.trim();
            if (!isValidSalesforceId(propertyId)) {
                return createResponse(false, 400, 'Invalid propertyId', null);
            }

            List<User> matchedUsers = [SELECT Id, ContactId, Contact.AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
            if (matchedUsers.isEmpty()) {
                return createResponse(false, 404, 'User not found', null);
            }
            Id accountId = matchedUsers[0].Contact != null ? matchedUsers[0].Contact.AccountId : null;

            List<Project__c> matchedProjects = [SELECT Id, Name, Email__c,Project_Location__Street__s, Project_Location__City__s,Project_Location__StateCode__s, Project_Location__PostalCode__s,Project_Location__CountryCode__s,Location__Latitude__s, Location__Longitude__s FROM Project__c WHERE Id = :propertyId WITH SYSTEM_MODE LIMIT 1];
            if (matchedProjects.isEmpty()) {
                return createResponse(false, 404, 'Property not found', null);
            }
            Project__c project = matchedProjects[0];

            List<CardWrapper> cards = new List<CardWrapper>();
            cards.add(buildPropertyAddressCard(project));
            cards.add(buildEmailCard(project));
            cards.add(buildCsContactCard(accountId));
            cards.add(buildCorporateAddressCard());

            DataWrapper data = new DataWrapper();
            data.propertyId   = String.valueOf(project.Id);
            data.propertyName = project.Name;
            data.cards         = cards;

            return createResponse(true, 200, 'Contact details retrieved successfully', data);
        } catch (Exception e) {
            System.debug('Error in API_LetsTalk.buildLetsTalkResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_LetsTalk', 'buildLetsTalkResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving contact details', null);
        }
    }

    private static CardWrapper buildPropertyAddressCard(Project__c project) {
        CardWrapper card = new CardWrapper();
        card.type        = 'address';
        card.title        = 'Property Address';
        card.body          = buildProjectAddress(project);
        card.actionLabel  = 'Open Location on Maps';

        MapActionWrapper action = new MapActionWrapper();
        action.kind      = 'map';
        action.latitude  = project.Location__Latitude__s;
        action.longitude = project.Location__Longitude__s;
        card.action = action;

        return card;
    }

    private static CardWrapper buildEmailCard(Project__c project) {
        CardWrapper card = new CardWrapper();
        card.type       = 'email';
        card.title       = 'Email';
        card.body         = project.Email__c;
        card.actionLabel = 'Email us';

        EmailActionWrapper action = new EmailActionWrapper();
        action.kind    = 'email';
        action.address = project.Email__c;
        action.subject = 'Enquiry — ' + project.Name;
        card.action = action;

        return card;
    }

    private static CardWrapper buildCsContactCard(Id accountId) {
        CardWrapper card = new CardWrapper();
        card.type       = 'phone';
        card.title       = 'CS Contact';
        card.actionLabel = 'Call us';

        Map<String, String> csContactBody = new Map<String, String>();
        String firstAvailablePhone = null;

        if (accountId != null) {
            for (Opportunity opp : [SELECT Id, CS_Member__c, CS_Member__r.Name, CS_Member__r.Phone, Unit__r.Unit_Name_Code__c FROM Opportunity WHERE AccountId = :accountId AND CS_Member__c != null WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC]) {
                if (opp.CS_Member__r == null) {
                    continue;
                }
                String csName  = opp.CS_Member__r.Name;
                String csPhone = opp.CS_Member__r.Phone;
                if (String.isBlank(csName) && String.isBlank(csPhone)) {
                    continue;
                }
			  
                csContactBody.put(opp.Unit__r.Unit_Name_Code__c, (csName != null ? csName : '') + ' : ' + (csPhone != null ? csPhone : ''));
                if (firstAvailablePhone == null && String.isNotBlank(csPhone)) {
                    firstAvailablePhone = csPhone;
                }
            }
        }

        card.body = csContactBody;

        PhoneActionWrapper action = new PhoneActionWrapper();
        action.kind        = 'phone';
        action.phoneNumber = firstAvailablePhone;
        card.action = action;

        return card;
    }

    private static CardWrapper buildCorporateAddressCard() {
        CardWrapper card = new CardWrapper();
        card.type       = 'address';
        card.title       = 'Corporate Address';
        card.actionLabel = 'Open Location on Maps';

        MapActionWrapper action = new MapActionWrapper();
        action.kind = 'map';

        List<Company__c> matchedCompanies = [SELECT Id, Address__c,Address__Street__s, Address__City__s, Address__StateCode__s,Address__PostalCode__s, Address__CountryCode__s,Location__Latitude__s, Location__Longitude__s FROM Company__c WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];

        if (!matchedCompanies.isEmpty()) {
            Company__c company = matchedCompanies[0];
            card.body        = buildCompanyAddress(company);
            action.latitude  = company.Location__Latitude__s;
            action.longitude = company.Location__Longitude__s;
        }

        card.action = action;
        return card;
    }

    private static String buildProjectAddress(Project__c project) {
        List<String> addressParts = new List<String>{
            project.Project_Location__Street__s,
            project.Project_Location__City__s,
            project.Project_Location__StateCode__s,
            project.Project_Location__PostalCode__s,
            project.Project_Location__CountryCode__s
        };
        return joinNonBlank(addressParts);
    }

    private static String buildCompanyAddress(Company__c company) {
        List<String> addressParts = new List<String>{
            company.Address__Street__s,
            company.Address__City__s,
            company.Address__StateCode__s,
            company.Address__PostalCode__s,
            company.Address__CountryCode__s
        };
        return joinNonBlank(addressParts);
    }

    private static String joinNonBlank(List<String> parts) {
        List<String> nonBlankParts = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                nonBlankParts.add(part);
            }
        }
        return nonBlankParts.isEmpty() ? null : String.join(nonBlankParts, ', ');
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static LetsTalkResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, DataWrapper data) {
        LetsTalkResponse apiResponse = new LetsTalkResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class LetsTalkResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public DataWrapper data;
    }

    public class DataWrapper {
        public String propertyId;
        public String propertyName;
        public List<CardWrapper> cards;
    }

    public class CardWrapper {
        public String type;
        public String title;
        public Object body;
        public String actionLabel;
        public Object action;
    }

    public class MapActionWrapper {
        public String kind;
        public Decimal latitude;
        public Decimal longitude;
    }

    public class EmailActionWrapper {
        public String kind;
        public String address;
        public String subject;
    }

    public class PhoneActionWrapper {
        public String kind;
        public String phoneNumber;
    }
}