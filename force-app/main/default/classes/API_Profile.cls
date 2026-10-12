@RestResource(urlMapping='/api/v1/profile/picture')
global without sharing class API_Profile {

    private static final String PICTURE_TITLE_PREFIX = 'profile_picture_';
    private static final String FILE_API_VERSION      = '60.0';
    private static final Integer MAX_IMAGE_BYTES       = 4194304;

    private static final Set<String> ALLOWED_CONTENT_TYPES = new Set<String>{'image/jpeg', 'image/png', 'image/webp'};

    @HttpPost
    global static void uploadImage() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            UploadRequest body = parseBody(response);
            if (body == null) {
                return;
            }

            ValidatedImage image = validateImage(response, body);
            if (image == null) {
                return;
            }

            handlePictureUpload(response, image);
        } catch (Exception e) {
            System.debug('Error in API_Profile.uploadImage ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Profile', 'uploadImage', e, null, 'SFA - SFDC');
            send(response, 500, createResponse(false, 500, 'Failed to upload profile picture', null));
        }
    }

    private static void handlePictureUpload(RestResponse response, ValidatedImage image) {
        Id userId = UserInfo.getUserId();
        FileResult file = saveFileForUser(userId, PICTURE_TITLE_PREFIX + userId, image.fileName, image.data);

        UploadData data = new UploadData();
        data.profilePictureUrl = URL.getOrgDomainUrl().toExternalForm() + '/services/data/v' + FILE_API_VERSION +
            '/sobjects/ContentVersion/' + file.contentVersionId + '/VersionData';
        data.fileName = image.fileName;

        send(response, 201, createResponse(true, 201, 'Profile picture uploaded successfully', data));
    }

    private static UploadRequest parseBody(RestResponse response) {
        UploadRequest body;
        try {
            body = (UploadRequest) JSON.deserialize(RestContext.request.requestBody.toString(), UploadRequest.class);
        } catch (Exception e) {
            send(response, 400, createResponse(false, 400, 'Invalid request body', null));
            return null;
        }
        if (body == null) {
            send(response, 400, createResponse(false, 400, 'Invalid request body', null));
            return null;
        }
        return body;
    }

    private static ValidatedImage validateImage(RestResponse response, UploadRequest body) {
        if (String.isBlank(body.fileName) || String.isBlank(body.contentType) || String.isBlank(body.base64Data)) {
            send(response, 400, createResponse(false, 400, 'fileName, contentType and base64Data are required', null));
            return null;
        }

        if (!ALLOWED_CONTENT_TYPES.contains(body.contentType.trim().toLowerCase())) {
            send(response, 400, createResponse(false, 400, 'Only image files are allowed', null));
            return null;
        }

        Blob imageData;
        try {
            imageData = EncodingUtil.base64Decode(body.base64Data.trim());
        } catch (Exception e) {
            send(response, 400, createResponse(false, 400, 'Invalid base64Data', null));
            return null;
        }
        if (imageData == null || imageData.size() == 0) {
            send(response, 400, createResponse(false, 400, 'Invalid base64Data', null));
            return null;
        }
        if (imageData.size() > MAX_IMAGE_BYTES) {
            send(response, 400, createResponse(false, 400, 'Image size must not exceed 4 MB', null));
            return null;
        }

        ValidatedImage image = new ValidatedImage();
        image.fileName = body.fileName.trim();
        image.data     = imageData;
        return image;
    }

    private static FileResult saveFileForUser(Id userId, String title, String fileName, Blob data) {
        List<ContentDocumentLink> existingLinks = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :userId AND ContentDocument.Title = :title WITH SYSTEM_MODE LIMIT 1];

        ContentVersion version = new ContentVersion();
        version.Title        = title;
        version.PathOnClient = fileName;
        version.VersionData  = data;
        if (!existingLinks.isEmpty()) {
            version.ContentDocumentId = existingLinks[0].ContentDocumentId;
        }

        Id networkId = getUserNetworkId(userId);
        if (networkId != null) {
            version.NetworkId = networkId;
        }
        insert as system version;

        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id LIMIT 1].ContentDocumentId;

        if (existingLinks.isEmpty()) {
            ContentDocumentLink link = new ContentDocumentLink();
            link.ContentDocumentId = contentDocumentId;
            link.LinkedEntityId    = userId;
            link.ShareType         = 'V';
            link.Visibility        = 'AllUsers';
            insert as system link;
        }

        FileResult result = new FileResult();
        result.contentVersionId  = version.Id;
        result.contentDocumentId = contentDocumentId;
        return result;
    }

    private static Id getUserNetworkId(Id userId) {
        Id current = Network.getNetworkId();
        if (current != null) {
            return current;
        }
        List<NetworkMember> memberships = [SELECT NetworkId FROM NetworkMember WHERE MemberId = :userId AND Network.Status = 'Live' LIMIT 1];
        return memberships.isEmpty() ? null : memberships[0].NetworkId;
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

    public class UploadRequest {
        public String fileName;
        public String contentType;
        public String base64Data;
    }

    public class ValidatedImage {
        public String fileName;
        public Blob data;
    }

    public class FileResult {
        public Id contentVersionId;
        public Id contentDocumentId;
    }

    public class ResponseWrapper {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public Object data;
    }

    public class UploadData {
        public String profilePictureUrl;
        public String fileName;
    }
}