<aura:application access="GLOBAL" extends="ltng:outApp">
    <!--
        Lightning Out application. This is what $Lightning.use() loads on the
        Visualforce page before $Lightning.createComponent() can instantiate
        customerProtalAura (and therefore the customerProtal LWC).
    -->
    <aura:dependency resource="c:customerPortalAura" type="COMPONENT" />
</aura:application>