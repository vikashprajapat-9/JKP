public with sharing class PartnerWebPortalMyTeamController {

    public class TeamStats {
        @AuraEnabled public Integer totalLeads;
        @AuraEnabled public Integer totalBookings;   // hardcoded for now
        @AuraEnabled public Integer totalExecutives; // hardcoded for now
    }

    public class TeamMember {
        @AuraEnabled public Id userId;
        @AuraEnabled public String initials;
        @AuraEnabled public String fullName;
        @AuraEnabled public String role;
        @AuraEnabled public Integer leads;
        @AuraEnabled public Integer bookings;        // hardcoded for now
        @AuraEnabled public String avatarColorClass; // for tile background
    }

    public class MyTeamResponse {
        @AuraEnabled public TeamStats stats;
        @AuraEnabled public List<TeamMember> members;
    }

    @AuraEnabled(cacheable=true)
    public static MyTeamResponse getMyTeam() {
        MyTeamResponse response = new MyTeamResponse();

        // -----------------------------------------------------------
        // 1) TEAM MEMBERS — pull from User (can be refined later)
        // -----------------------------------------------------------
        List<User> users = [
            SELECT Id, Name, Title
            FROM User
            WHERE IsActive = true
            LIMIT 10
        ];

        List<TeamMember> members = new List<TeamMember>();
        Integer colorIndex = 0;
        List<String> colors = new List<String>{
            'avatar-blue', 'avatar-yellow', 'avatar-green', 'avatar-purple'
        };

        for (User u : users) {
            TeamMember m = new TeamMember();
            m.userId   = u.Id;
            m.fullName = u.Name;
            m.role     = String.isNotBlank(u.Title) ? u.Title : 'Executive';
            m.initials = buildInitials(u.Name);
            m.leads    = 0;    // replaced below with aggregate
            m.bookings = 0;    // hardcoded — replace later
            m.avatarColorClass = colors[Math.mod(colorIndex, colors.size())];
            members.add(m);
            colorIndex++;
        }

        // -----------------------------------------------------------
        // 2) LEADS PER OWNER — dynamic aggregate query
        // -----------------------------------------------------------
        Map<Id, Integer> leadsByOwner = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT OwnerId, COUNT(Id) cnt
            FROM Lead
            WHERE IsConverted = false
              AND OwnerId IN :users
            GROUP BY OwnerId
        ]) {
            leadsByOwner.put(
                (Id) ar.get('OwnerId'),
                (Integer) ar.get('cnt')
            );
        }

        Integer totalLeads = 0;
        for (TeamMember m : members) {
            Integer count = leadsByOwner.containsKey(m.userId)
                ? leadsByOwner.get(m.userId)
                : 0;
            m.leads = count;
            totalLeads += count;
        }

        // -----------------------------------------------------------
        // 3) TOP-LEVEL STATS
        // -----------------------------------------------------------
        TeamStats stats = new TeamStats();
        stats.totalLeads       = totalLeads;
        stats.totalBookings    = 156;  // hardcoded for now
        stats.totalExecutives  = 4;    // hardcoded for now

        response.stats   = stats;
        response.members = members;
        return response;
    }

    private static String buildInitials(String fullName) {
        if (String.isBlank(fullName)) return '';
        List<String> parts = fullName.trim().split('\\s+');
        String first = parts[0].substring(0, 1);
        String last  = parts.size() > 1
            ? parts[parts.size() - 1].substring(0, 1)
            : '';
        return (first + last).toUpperCase();
    }
}