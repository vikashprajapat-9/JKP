@RestResource(urlMapping='/api/v1/profile')
global without sharing class API_ProfileGet {

    private static final String PICTURE_TITLE_PREFIX = 'profile_picture_';

    private static final String PHONE_COUNTRY_CODE = '+94';
    private static final String PHONE_ISO_CODE     = 'LK';

    @HttpGet
    global static void getProfile() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            Id userId = UserInfo.getUserId();
            List<User> users = [SELECT Id, FirstName, LastName, Name, Email, Phone, Contact.Salutation FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
            if (users.isEmpty()) {
                send(response, 404, createResponse(false, 404, 'User not found', null));
                return;
            }
            User user = users[0];

            ProfileData data = new ProfileData();
            data.userId               = String.valueOf(user.Id);
            data.salutation           = user.Contact != null ? user.Contact.Salutation : null;
            data.firstName            = user.FirstName;
            data.lastName             = user.LastName;
            data.fullName             = user.Name;
            data.email                = user.Email;
            data.phone                = parsePhone(user.Phone);
            data.profilePictureBase64 = getProfilePictureBase64(userId);

            send(response, 200, createResponse(true, 200, 'Profile retrieved successfully', data));
        } catch (Exception e) {
            System.debug('Error in API_ProfileGet.getProfile ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_ProfileGet', 'getProfile', e, null, 'SFA - SFDC');
            send(response, 500, createResponse(false, 500, 'Failed to retrieve profile', null));
        }
    }

    private static String getProfilePictureBase64(Id userId) {
        String pictureTitle = PICTURE_TITLE_PREFIX + userId;

        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :userId AND ContentDocument.Title = :pictureTitle WITH SYSTEM_MODE LIMIT 1];
        if (links.isEmpty()) {
            return null;
        }

        List<ContentVersion> versions = [SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :links[0].ContentDocumentId AND IsLatest = true WITH SYSTEM_MODE LIMIT 1];
        if (versions.isEmpty() || versions[0].VersionData == null) {
            return null;
        }

        return EncodingUtil.base64Encode(versions[0].VersionData);
    }

    private static PhoneWrapper parsePhone(String rawPhone) {
        if (String.isBlank(rawPhone)) {
            return null;
        }
        String digits = rawPhone.replaceAll('[^0-9]', '');
        if (digits.startsWith('94') && digits.length() > 9) {
            digits = digits.substring(2);
        } else if (digits.startsWith('0')) {
            digits = digits.substring(1);
        }
        if (String.isBlank(digits)) {
            return null;
        }
        PhoneWrapper phone = new PhoneWrapper();
        phone.countryCode    = PHONE_COUNTRY_CODE;
        phone.isoCode        = PHONE_ISO_CODE;
        phone.nationalNumber = digits;
        return phone;
    }

    private static ResponseWrapper createResponse(Boolean success, Integer statusCode, String message, Object data) {
        ResponseWrapper response = new ResponseWrapper();
        response.success    = success;
        response.statusCode = statusCode;
        response.message    = message;
        response.data       = data;
        return response;
    }

    private static void send(RestResponse response, Integer statusCode, ResponseWrapper body) {
        response.statusCode   = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    public class ResponseWrapper {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public Object data;
    }

    public class ProfileData {
        public String userId;
        public String salutation;
        public String firstName;
        public String lastName;
        public String fullName;
        public String email;
        public PhoneWrapper phone;
        public String profilePictureBase64;
    }

    public class PhoneWrapper {
        public String countryCode;
        public String isoCode;
        public String nationalNumber;
    }
}