import { LightningElement, wire } from 'lwc';
import getDashboard from '@salesforce/apex/PartnerPortalDashboard.getDashboard';
import getCurrentUser from '@salesforce/apex/PartnerPortalDashboard.getCurrentUser';

const NO_VALUE = '–';
const LOAD_ERROR = 'Your dashboard could not be loaded right now. Please try again.';

export default class PartnerWebPortalDashboard extends LightningElement {
    // The team's figures (the partner's and their executives'), or null until they arrive
    figures = null;
    error;
    userName = '';

    connectedCallback() {
        this.loadFigures();
    }

    async loadFigures() {
        try {
            this.figures = await getDashboard();
            this.error = undefined;
        } catch (e) {
            this.figures = null;
            this.error = (e && e.body && e.body.message) || LOAD_ERROR;
        }
    }

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
        const f = this.figures;
        const number = value => (f ? String(Number(value) || 0) : NO_VALUE);
        return [
            { key: 'leads', label: 'Total Leads', value: number(f && f.totalLeads), icon: 'utility:groups' },
            { key: 'pipeline', label: 'Active Pipeline', value: number(f && f.activePipeline), icon: 'utility:activity' },
            { key: 'visits', label: 'Site Visits', value: number(f && f.siteVisits), icon: 'utility:location' },
            { key: 'bookings', label: 'Bookings', value: number(f && f.bookings), icon: 'utility:ribbon' },
            { key: 'sales', label: 'Sales', value: number(f && f.sales), icon: 'utility:chart' },
            {
                key: 'conversion',
                label: 'Conversion rate (site visits to sales)',
                value: f ? (Number(f.conversionRate) || 0) + '%' : NO_VALUE,
                icon: 'utility:trending'
            },
            {
                key: 'revenue',
                label: 'Total sales revenue generated',
                value: f ? this.money(f.salesRevenue, f.currencyCode) : NO_VALUE,
                icon: 'utility:currency'
            },
            {
                key: 'commission',
                label: 'Commission income',
                value: 'Development in progress',
                icon: 'utility:moneybag',
                valueClass: 'kpi-value kpi-value_note'
            }
        ].map(kpi => ({ valueClass: 'kpi-value', ...kpi }));
    }

    // For example "LKR 1,250,000"
    money(amount, currencyCode) {
        const whole = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(Number(amount) || 0);
        return (currencyCode ? currencyCode + ' ' : '') + whole;
    }

    // ================= WIRES =================

    @wire(getCurrentUser)
    wireduser({ data }) {
        if (data) {
            this.userName = data;
        }
    }
}