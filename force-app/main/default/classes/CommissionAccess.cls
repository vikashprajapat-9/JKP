// Who may do what in Commission Setup. A capability is held through the user's role or profile,
// as listed in Commission Setting (custom metadata): no role or profile name lives in code.
public without sharing class CommissionAccess {

    public static final String CONFIGURE = 'CONFIGURE', APPROVE = 'APPROVE', TARGETS = 'TARGETS', VIEW = 'VIEW', ALERT = 'ALERT';

    // The reporting line is followed at most this many levels down (one query per level)
    private static final Integer MAX_LEVELS = 6;

    // One query per user and transaction
    private static Map<Id, User> people = new Map<Id, User>();
    private static Map<Id, Set<Id>> lines = new Map<Id, Set<Id>>();

    public static Boolean can(String capability) {
        return can(capability, UserInfo.getUserId());
    }

    public static Boolean can(String capability, Id userId) {
        User person = personOf(userId);
        if (person == null || capability == null) {
            return false;
        }
        Commission_Setting__mdt setting = CommissionCatalog.setting();
        if (capability == CONFIGURE) {
            return holds(person, setting.Configure_Roles__c, setting.Configure_Profiles__c);
        }
        if (capability == APPROVE) {
            return holds(person, setting.Approve_Roles__c, setting.Approve_Profiles__c);
        }
        if (capability == TARGETS) {
            return holds(person, setting.Target_Roles__c, setting.Target_Profiles__c);
        }
        if (capability == ALERT) {
            return holds(person, setting.Alert_Roles__c, null);
        }
        if (capability == VIEW) {
            // Anyone who configures, approves or maintains targets can also read
            return holds(person, setting.View_Roles__c, setting.View_Profiles__c)
                || holds(person, setting.Configure_Roles__c, setting.Configure_Profiles__c)
                || holds(person, setting.Approve_Roles__c, setting.Approve_Profiles__c)
                || holds(person, setting.Target_Roles__c, setting.Target_Profiles__c);
        }
        return false;
    }

    // Stops the request with a message for the screen when the running user lacks the capability
    public static void require(String capability) {
        if (!can(capability)) {
            throw CommissionDto.error(refusal(capability));
        }
    }

    // What a user without the capability is told
    public static String refusal(String capability) {
        if (capability == CONFIGURE) {
            return System.Label.Commission_Rule_Configure_Only;
        }
        if (capability == APPROVE) {
            return System.Label.Commission_Rule_Approve_Only;
        }
        if (capability == TARGETS) {
            return System.Label.Commission_Rule_Targets_Only;
        }
        return System.Label.Commission_Common_No_Access;
    }

    // Not limited to a reporting line: the profile is listed for targets, or the user only reads
    public static Boolean seesEveryone() {
        User person = personOf(UserInfo.getUserId());
        if (person == null) {
            return false;
        }
        if (inList(profileName(person), CommissionCatalog.setting().Target_Profiles__c)) {
            return true;
        }
        return can(VIEW) && !can(TARGETS);
    }

    // The running user may approve a version they entered or edited themselves
    public static Boolean selfApprovalAllowed() {
        return selfApprovalAllowed(UserInfo.getUserId());
    }

    public static Boolean selfApprovalAllowed(Id userId) {
        User person = personOf(userId);
        return person != null && inList(profileName(person), CommissionCatalog.setting().Self_Approval_Profiles__c);
    }

    // The running user's role is named on an active designation
    public static Boolean isPayee() {
        return isPayee(UserInfo.getUserId());
    }

    public static Boolean isPayee(Id userId) {
        User person = personOf(userId);
        String role = person == null ? null : roleName(person);
        if (String.isBlank(role)) {
            return false;
        }
        for (CommissionDto.Designation designation : CommissionCatalog.designations()) {
            if (designation.userRoles != null && designation.userRoles.contains(role)) {
                return true;
            }
        }
        return false;
    }

    public static CommissionDto.Flags flags() {
        CommissionDto.Flags result = new CommissionDto.Flags();
        result.canConfigure = can(CONFIGURE);
        result.canApprove = can(APPROVE);
        result.canManageTargets = can(TARGETS);
        result.canView = can(VIEW);
        result.isPayee = isPayee();
        result.userId = UserInfo.getUserId();
        result.userName = UserInfo.getName();
        return result;
    }

    // Active internal users who hold the capability: Id, Name, Email, ProfileId, UserRoleId (and the role name, profile name and manager)
    public static List<User> usersWho(String capability) {
        Commission_Setting__mdt setting = CommissionCatalog.setting();
        Set<String> roles = new Set<String>();
        Set<String> profiles = new Set<String>();
        if (capability == CONFIGURE || capability == VIEW) {
            roles.addAll(CommissionCatalog.listOf(setting.Configure_Roles__c));
            profiles.addAll(CommissionCatalog.listOf(setting.Configure_Profiles__c));
        }
        if (capability == APPROVE || capability == VIEW) {
            roles.addAll(CommissionCatalog.listOf(setting.Approve_Roles__c));
            profiles.addAll(CommissionCatalog.listOf(setting.Approve_Profiles__c));
        }
        if (capability == TARGETS || capability == VIEW) {
            roles.addAll(CommissionCatalog.listOf(setting.Target_Roles__c));
            profiles.addAll(CommissionCatalog.listOf(setting.Target_Profiles__c));
        }
        if (capability == VIEW) {
            roles.addAll(CommissionCatalog.listOf(setting.View_Roles__c));
            profiles.addAll(CommissionCatalog.listOf(setting.View_Profiles__c));
        }
        if (capability == ALERT) {
            roles.addAll(CommissionCatalog.listOf(setting.Alert_Roles__c));
        }
        if (roles.isEmpty() && profiles.isEmpty()) {
            return new List<User>();
        }
        List<User> users = [
            SELECT Id, Name, Email, IsActive, ProfileId, Profile.Name, UserRoleId, UserRole.DeveloperName, ManagerId
            FROM User
            WHERE IsActive = true AND UserType = 'Standard'
              AND (UserRole.DeveloperName IN :roles OR Profile.Name IN :profiles)
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 2000
        ];
        remember(users);
        return users;
    }

    // Active internal users holding one of these roles (UserRole.DeveloperName; upper or lower case does not matter)
    public static List<User> usersInRoles(Set<String> roleDeveloperNames) {
        Set<String> roles = new Set<String>();
        if (roleDeveloperNames != null) {
            for (String name : roleDeveloperNames) {
                if (String.isNotBlank(name)) {
                    roles.add(name.trim().toLowerCase());
                }
            }
        }
        if (roles.isEmpty()) {
            return new List<User>();
        }
        List<User> users = [
            SELECT Id, Name, Email, IsActive, ProfileId, Profile.Name, UserRoleId, UserRole.DeveloperName, ManagerId
            FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND UserRole.DeveloperName IN :roles
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 2000
        ];
        remember(users);
        return users;
    }

    // Active users below this user through ManagerId, at any depth (at most six levels), without the user.
    // An inactive manager in between does not cut off the people below them.
    public static Set<Id> reportingLine(Id managerId) {
        if (managerId == null) {
            return new Set<Id>();
        }
        if (lines.containsKey(managerId)) {
            return lines.get(managerId).clone();
        }
        Set<Id> below = new Set<Id>();
        Set<Id> seen = new Set<Id>{ managerId };
        Set<Id> level = new Set<Id>{ managerId };
        for (Integer depth = 0; depth < MAX_LEVELS && !level.isEmpty(); depth++) {
            Set<Id> next = new Set<Id>();
            for (User report : [SELECT Id, IsActive FROM User WHERE ManagerId IN :level WITH SYSTEM_MODE LIMIT 5000]) {
                // A user is taken once, so a loop in the manager field cannot run for ever
                if (seen.contains(report.Id)) {
                    continue;
                }
                seen.add(report.Id);
                next.add(report.Id);
                if (report.IsActive) {
                    below.add(report.Id);
                }
            }
            level = next;
        }
        lines.put(managerId, below);
        return below.clone();
    }

    // Forgets what was read about users (tests switch users and settings)
    @TestVisible
    static void reset() {
        people.clear();
        lines.clear();
    }

    // ------------------------------------------------------------ helpers

    private static User personOf(Id userId) {
        if (userId == null) {
            return null;
        }
        if (!people.containsKey(userId)) {
            List<User> found = [
                SELECT Id, Name, Email, IsActive, ProfileId, Profile.Name, UserRoleId, UserRole.DeveloperName, ManagerId
                FROM User
                WHERE Id = :userId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            people.put(userId, found.isEmpty() ? null : found[0]);
        }
        return people.get(userId);
    }

    // Users just read by a list query need no second query when their rights are asked for
    private static void remember(List<User> users) {
        for (User person : users) {
            if (!people.containsKey(person.Id)) {
                people.put(person.Id, person);
            }
        }
    }

    private static Boolean holds(User person, String roleList, String profileList) {
        return inList(roleName(person), roleList) || inList(profileName(person), profileList);
    }

    private static Boolean inList(String name, String listText) {
        return String.isNotBlank(name) && CommissionCatalog.listOf(listText).contains(name);
    }

    // Lower case, as CommissionCatalog.listOf returns the lists
    private static String roleName(User person) {
        return person.UserRoleId == null || person.UserRole == null || person.UserRole.DeveloperName == null
            ? null : person.UserRole.DeveloperName.toLowerCase();
    }

    private static String profileName(User person) {
        return person.ProfileId == null || person.Profile == null || person.Profile.Name == null
            ? null : person.Profile.Name.toLowerCase();
    }
}