/*
================================================================================
MISSING / NEED TO VERIFY
================================================================================
1. "Name" field mapping
   - The request asks for an independent "name" update. This class maps
     it to firstName/lastName on User (same fields the original,
     pre-reduction version of this class used), each independently
     optional, rather than a single combined "name" string. Confirm this
     matches what the frontend sends - if it actually sends one combined
     "name" field, this needs to change to split/parse it instead.

Confirmed and used directly (same validation rules as the original,
pre-reduction version of this class):
- User.FirstName / User.LastName (max 40 / 80 chars)
- User.Phone, validated against the same phone pattern used previously.
================================================================================

HOW THIS ENDPOINT NOW WORKS
--------------------------------------------------------------------------
Every one of the three things this endpoint can change - profile picture,
name (firstName/lastName), phone - is independently optional. The caller
can send any one, any combination, or all three in a single POST, and only
the fields actually present in the request body are validated and applied.
Sending none of them is not an error; the response simply reports that
nothing was updated.
================================================================================
*/
@RestResource(urlMapping='/api/v1/profile/picture')
global without sharing class API_Profile {

    private static final String PICTURE_TITLE_PREFIX = 'profile_picture_';
    private static final String FILE_API_VERSION      = '60.0';
    private static final Integer MAX_IMAGE_BYTES      = 4194304;

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

            Boolean imageProvided = !isImageOmitted(body);
            Boolean nameProvided  = !isNameOmitted(body);
            Boolean phoneProvided = !isPhoneOmitted(body);

            if (!imageProvided && !nameProvided && !phoneProvided) {
                send(response, 200, createResponse(true, 200, 'No changes provided; nothing to update', null));
                return;
            }

            String nameError = nameProvided ? validateName(body) : null;
            if (nameError != null) {
                send(response, 400, createResponse(false, 400, nameError, null));
                return;
            }

            String phoneError = phoneProvided ? validatePhone(body) : null;
            if (phoneError != null) {
                send(response, 400, createResponse(false, 400, phoneError, null));
                return;
            }

            ValidatedImage image = null;
            if (imageProvided) {
                image = validateImage(response, body);
                if (image == null) {
                    return; // validateImage already sent the error response
                }
            }

            Id userId = UserInfo.getUserId();
            User userToUpdate = new User(Id = userId);
            Boolean userFieldsChanged = false;

            if (nameProvided) {
                if (body.firstName != null) {
                    userToUpdate.FirstName = body.firstName;
                }
                if (body.lastName != null) {
                    userToUpdate.LastName = body.lastName;
                }
                userFieldsChanged = true;
            }
            if (phoneProvided) {
                userToUpdate.Phone = body.phone;
                userFieldsChanged = true;
            }

            UploadData data = new UploadData();

            if (imageProvided) {
                FileResult file = saveFileForUser(userId, PICTURE_TITLE_PREFIX + userId, image.fileName, image.data);
                data.profilePictureUrl = URL.getOrgDomainUrl().toExternalForm() + '/services/data/v' + FILE_API_VERSION +
                    '/sobjects/ContentVersion/' + file.contentVersionId + '/VersionData';
                data.fileName = image.fileName;
            }

            if (userFieldsChanged) {
                update as system userToUpdate;
            }
            if (nameProvided || phoneProvided) {
                User saved = [SELECT FirstName, LastName, Phone FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
                data.firstName = saved.FirstName;
                data.lastName  = saved.LastName;
                data.phone     = saved.Phone;
            }

            send(response, imageProvided ? 201 : 200, createResponse(true, imageProvided ? 201 : 200, 'Profile updated successfully', data));
        } catch (Exception e) {
            System.debug('Error in API_Profile.uploadImage ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_Profile', 'uploadImage', e, null, 'SFA - SFDC');
            send(response, 500, createResponse(false, 500, 'Failed to update profile', null));
        }
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

    // ---- Independent "is this field present at all" checks ----

    private static Boolean isImageOmitted(UploadRequest body) {
        return String.isBlank(body.fileName) && String.isBlank(body.contentType) && String.isBlank(body.base64Data);
    }

    private static Boolean isNameOmitted(UploadRequest body) {
        return String.isBlank(body.firstName) && String.isBlank(body.lastName);
    }

    private static Boolean isPhoneOmitted(UploadRequest body) {
        return String.isBlank(body.phone);
    }

    // ---- Per-field validation, only run when that field was provided ----

    private static String validateName(UploadRequest body) {
        if (body.firstName != null) {
            body.firstName = body.firstName.trim();
            if (String.isBlank(body.firstName)) {
                return 'firstName must not be blank';
            }
            if (body.firstName.length() > 40) {
                return 'firstName must not exceed 40 characters';
            }
        }
        if (body.lastName != null) {
            body.lastName = body.lastName.trim();
            if (String.isBlank(body.lastName)) {
                return 'lastName must not be blank';
            }
            if (body.lastName.length() > 80) {
                return 'lastName must not exceed 80 characters';
            }
        }
        return null;
    }

    private static String validatePhone(UploadRequest body) {
        body.phone = body.phone.trim();
        if (!Pattern.matches('^[0-9+()\\-.\\s]{5,40}$', body.phone)) {
            return 'Invalid phone number';
        }
        return null;
    }

    // If ANY one of fileName/contentType/base64Data is provided, all three
    // are required together, since a partial image payload can't be
    // decoded or saved.
    private static ValidatedImage validateImage(RestResponse response, UploadRequest body) {
        if (String.isBlank(body.fileName) || String.isBlank(body.contentType) || String.isBlank(body.base64Data)) {
            send(response, 400, createResponse(false, 400, 'fileName, contentType and base64Data are all required when uploading a profile picture', null));
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
        public String firstName;
        public String lastName;
        public String phone;
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
        public String firstName;
        public String lastName;
        public String phone;
    }
}