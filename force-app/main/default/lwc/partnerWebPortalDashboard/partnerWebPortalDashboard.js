import { LightningElement, wire } from 'lwc';
import getTotalLead from '@salesforce/apex/PartnerPortalDashboard.getLeaddetail';
import getTotalVisit from '@salesforce/apex/PartnerPortalDashboard.getSitedetail';
import getCurrentUser from '@salesforce/apex/PartnerPortalDashboard.getCurrentUser';

export default class PartnerWebPortalDashboard extends LightningElement {
    leadcount = '';
    visitcount = '';
    error;
    userName = '';

    // ================= PRESENTATION =================
    get greeting() {
        const hour = new Date().getHours();
        if (hour < 12) {
            return 'Good Morning';
        }
        if (hour < 17) {
            return 'Good Afternoon';
        }
        return 'Good Evening';
    }

    // Static commission slabs shown in the hero banner (from Figma)
    get slabs() {
        return [
            {
                key: 'viman',
                name: 'VIMAN',
                rate: '2.5%',
                desc: 'Base Commission',
                note: '2.5% and an additional 0.5% if 5 or more units are sold'
            },
            { key: 'vauxhall', name: 'VAUXHALL DISTRICT', rate: '2.5%', desc: 'Base Rate' },
            {
                key: 'cinnamon',
                name: 'CINNAMON LIFE',
                rate: '3%',
                desc: 'Additional 1% 5 or more units are sold',
                current: true
            },
            { key: 'trizen', name: 'TRIZEN', rate: '2.5%', desc: 'Base Rate' }
        ].map((s) => ({ ...s, cardClass: s.current ? 'slab slab-current' : 'slab' }));
    }

    get kpis() {
        return [
            { key: 'leads', label: 'Total Leads', value: this.leadcount, icon: 'utility:groups' },
            { key: 'pipeline', label: 'Active Pipeline', value: '38', icon: 'utility:activity' },
            { key: 'visits', label: 'Site Visits', value: this.visitcount, icon: 'utility:location' },
            { key: 'bookings', label: 'Bookings', value: '07', icon: 'utility:ribbon' },
            { key: 'sales', label: 'Sales', value: '21', icon: 'utility:chart' },
            {
                key: 'conversion',
                label: 'Conversion rate (site visits to sales)',
                value: '78%',
                icon: 'utility:trending'
            },
            {
                key: 'revenue',
                label: 'Total sales revenue generated',
                value: 'LKR 5,000',
                icon: 'utility:currency'
            },
            { key: 'commission', label: 'Commission income', value: 'LKR 12,000', icon: 'utility:moneybag' }
        ];
    }

    // ================= WIRES =================
    @wire(getTotalLead)
    wiredLead({ data, error }) {
        if (data) {
            this.leadcount = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.leadcount = undefined;
        }
    }

    @wire(getTotalVisit)
    wiredVisit({ data, error }) {
        if (data) {
            this.visitcount = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.visitcount = undefined;
        }
    }

    @wire(getCurrentUser)
    wireduser({ data }) {
        if (data) {
            this.userName = data;
        }
    }
}