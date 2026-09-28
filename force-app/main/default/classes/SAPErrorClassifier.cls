/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : SAPErrorClassifier
 * Author          : Vamsi Krishna Reddy
 * Created Date    : Mar 18, 2026
 * Last Modified By: Vamsi Krishna Reddy
 * Last Modified On: Mar 18, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 18, 2026  │ Vamsi Krishna Reddy  │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class SAPErrorClassifier {

	public enum ErrorCategory {
        BUSINESS, TECHNICAL, MASTER_DATA, AUTH, RATE_LIMIT
    }

	// ─── Main Classifier ───────────────────────────────────────
    public static String classify(Integer httpStatus, String body) {

		// Null-safe body
		String safeBody = (body != null) ? body.toLowerCase() : '';

		// 1. AUTH — 401 Unauthorized / 403 Forbidden
        //    Your error: Status=Unauthorized, StatusCode=401 → hits HERE
        if (httpStatus == 401 || httpStatus == 403) {
            System.debug('ERROR CATEGORY --> Authentication Error | HTTP: ' + httpStatus);
            return getCategoryLabel(ErrorCategory.AUTH);
        }

		// 2. RATE LIMIT — 429 Too Many Requests
        if (httpStatus == 429) {
            System.debug('ERROR CATEGORY --> Rate Limit Error | HTTP: ' + httpStatus);
            return getCategoryLabel(ErrorCategory.RATE_LIMIT);
        }

		// 3. MASTER DATA — 404 or SAP body keywords
        if (httpStatus == 404
            || safeBody.contains('mdm')
            || safeBody.contains('not found')
            || safeBody.contains('does not exist')
            || safeBody.contains('no record found')
            || safeBody.contains('customer not found')
            || safeBody.contains('material not found')) {
            System.debug('ERROR CATEGORY --> Master Data Error | HTTP: ' + httpStatus);
            return getCategoryLabel(ErrorCategory.MASTER_DATA);
        }

		// 4. TECHNICAL — all 5xx
        if (httpStatus >= 500) {
            System.debug('ERROR CATEGORY --> Technical Error | HTTP: ' + httpStatus);
            return getCategoryLabel(ErrorCategory.TECHNICAL);
        }

		 // 5. BUSINESS — 400 / 422 or SAP business rule keywords
        if (httpStatus == 400 || httpStatus == 422
            || safeBody.contains('credit limit')
            || safeBody.contains('minimum order')
            || safeBody.contains('delivery date')
            || safeBody.contains('pricing condition')) {
            System.debug('ERROR CATEGORY --> Business Error | HTTP: ' + httpStatus);
            return getCategoryLabel(ErrorCategory.BUSINESS);
        }

		// 6. Fallback
        System.debug('ERROR CATEGORY --> Technical Error (Fallback) | HTTP: ' + httpStatus);
        return getCategoryLabel(ErrorCategory.TECHNICAL);
	}

	// ─── Should this category be retried? ──────────────────────
    public static Boolean shouldRetry(ErrorCategory cat, Integer retryCount) {
        if (cat == ErrorCategory.TECHNICAL || cat == ErrorCategory.RATE_LIMIT) {
            return retryCount < 3;
        }
        // AUTH, BUSINESS, MASTER_DATA → no auto retry
        return false;
    }

	// ─── Retry delay in seconds (exponential backoff) ──────────
    public static Integer retryDelaySeconds(Integer retryCount) {
        Integer[] delays = new Integer[]{ 60, 300, 900 };
        return (retryCount < 3) ? delays[retryCount] : 900;
    }

    // ─── Human-readable label ──────────────────────────────────
    public static String getCategoryLabel(ErrorCategory cat) {
        if (cat == ErrorCategory.AUTH)        return 'Authentication Error';
        if (cat == ErrorCategory.RATE_LIMIT)  return 'Rate Limit Error';
        if (cat == ErrorCategory.MASTER_DATA) return 'Master Data Error';
        if (cat == ErrorCategory.TECHNICAL)   return 'Technical Error';
        if (cat == ErrorCategory.BUSINESS)    return 'Business Error';
        return 'Unknown Error';
    }

    // ─── Alert owner? (for Flow / trigger routing) ─────────────
    public static String getOwnerAction(ErrorCategory cat) {
        if (cat == ErrorCategory.AUTH)        return 'Alert Integration/Security Team';
        if (cat == ErrorCategory.RATE_LIMIT)  return 'Auto Retry - Alert IT if persists';
        if (cat == ErrorCategory.MASTER_DATA) return 'Alert MDM / Data Governance Team';
        if (cat == ErrorCategory.TECHNICAL)   return 'Auto Retry - Alert IT Team';
        if (cat == ErrorCategory.BUSINESS)    return 'Notify Record Owner / Sales Team';
        return 'Alert IT Team';
    }


}