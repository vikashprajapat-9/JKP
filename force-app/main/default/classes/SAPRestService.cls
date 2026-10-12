@RestResource(urlMapping='/SAP/*')
global with sharing class SAPRestService {

    @HttpGet
    global static void doGet() {
        try {
            RestRequest request = RestContext.request;
            // String resourcePath = getResourcePath(request);

            // writeResponse(501, new Map<String, Object>{
            //     'success' => false,
            //     'message' => 'No handler is registered for GET ' + resourcePath + '.'
            // });
        } catch (IllegalArgumentException argEx) {
            logError('doGet', argEx);
            writeError(400, argEx.getMessage());
        } catch (Exception ex) {
            logError('doGet', ex);
            writeError(500, 'Internal server error.');
        }
    }

    @HttpPost
    global static void doPost() {
        try {
            RestRequest request = RestContext.request;
          //  String resourcePath = getResourcePath(request);
            String requestBody = getRequestBody(request);

            // writeResponse(501, new Map<String, Object>{
            //     'success' => false,
            //     'message' => 'No handler is registered for POST ' + resourcePath + '.'
            // });
        } catch (IllegalArgumentException argEx) {
            logError('doPost', argEx);
            writeError(400, argEx.getMessage());
        } catch (Exception ex) {
            logError('doPost', ex);
            writeError(500, 'Internal server error.');
        }
    }

    @HttpPut
    global static void doPut() {
        try {
            RestRequest request = RestContext.request;
         //   String resourcePath = getResourcePath(request);
            String requestBody = getRequestBody(request);

            // writeResponse(501, new Map<String, Object>{
            //     'success' => false,
            //     'message' => 'No handler is registered for PUT ' + resourcePath + '.'
            // });
        } catch (IllegalArgumentException argEx) {
            logError('doPut', argEx);
            writeError(400, argEx.getMessage());
        } catch (Exception ex) {
            logError('doPut', ex);
            writeError(500, 'Internal server error.');
        }
    }

    // private static String getResourcePath(RestRequest request) {
    //     if (request == null || String.isBlank(request.requestURI)) {
    //         throw new IllegalArgumentException('Request URI is missing.');
    //     }

    //     Integer markerIndex = request.requestURI.indexOf('/SAP/');
    //     if (markerIndex < 0) {
    //         throw new IllegalArgumentException('Request URI is not a valid SAP service path.');
    //     }

    //     String resourcePath = request.requestURI.substring(markerIndex + 5).trim();
    //     if (String.isBlank(resourcePath)) {
    //         throw new IllegalArgumentException('Resource path is required.');
    //     }

    //     return resourcePath;
    // }

    private static String getRequestBody(RestRequest request) {
        String requestBody = request.requestBody == null ? null : request.requestBody.toString();
        if (String.isBlank(requestBody)) {
            throw new IllegalArgumentException('Request body is required.');
        }

        return requestBody;
    }

    private static void writeError(Integer statusCode, String message) {
        writeResponse(statusCode, new Map<String, Object>{
            'success' => false,
            'message' => String.isBlank(message) ? 'Request failed.' : message
        });
    }

    private static void writeResponse(Integer statusCode, Object body) {
        RestResponse response = RestContext.response;
        if (response == null) {
            return;
        }

        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(body == null ? new Map<String, Object>() : body));
    }

    private static void logError(String apexMethodName, Exception ex) {
        try {
            IntegrationLogUtility.captureError('SAPRestService', apexMethodName, ex, null, 'SAP - SFDC');
        } catch (Exception loggingEx) {
            System.debug(LoggingLevel.ERROR, 'SAPRestService.' + apexMethodName + ' failed to write integration log: ' + loggingEx.getMessage());
        }
    }
}