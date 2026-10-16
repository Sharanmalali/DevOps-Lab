// Exercise 9 - headless Jenkins bootstrap.
//
// Runs at controller startup from /var/jenkins_home/init.groovy.d. Creates a
// local admin/admin account and disables anonymous access, so the pipeline job
// can be created and triggered entirely via the REST API (Jenkins' API rejects
// anonymous writes).
//
// WARNING: credentials below are intentionally trivial and are ONLY for a
// throw-away lab container. Never use this in a real environment.
import jenkins.model.Jenkins
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

def jenkins = Jenkins.get()

if (!(jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
    def realm = new HudsonPrivateSecurityRealm(false)
    realm.createAccount("admin", "admin")
    jenkins.setSecurityRealm(realm)

    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    jenkins.setAuthorizationStrategy(strategy)

    jenkins.save()
    println("[init.groovy.d] Jenkins security realm configured (admin/admin).")
} else {
    println("[init.groovy.d] Security realm already configured; skipping.")
}
