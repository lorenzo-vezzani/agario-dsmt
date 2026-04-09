package it.unipi.dsmt.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "agario")
public class AgarioConfig {

    private String supervisorIp;
    private String selfErlangIp;
    private String supervisorCookie;
    private String supervisorMb;
    private String supervisorNodeName;

    public String getSupervisorIp() {
        return supervisorIp;
    }

    public void setSupervisorIp(String supervisorIp) {
        this.supervisorIp = supervisorIp;
    }

    public String getSelfErlangIp() {
        return selfErlangIp;
    }

    public void setSelfErlangIp(String selfErlangIp) {
        this.selfErlangIp = selfErlangIp;
    }

    public String getSupervisorCookie() {
        return supervisorCookie;
    }

    public void setSupervisorCookie(String supervisorCookie) {
        this.supervisorCookie = supervisorCookie;
    }

    public String getSupervisorMb() {
        return supervisorMb;
    }

    public void setSupervisorMb(String supervisorMb) {
        this.supervisorMb = supervisorMb;
    }

    public String getSupervisorNodeName() {
        return supervisorNodeName;
    }

    public void setSupervisorNodeName(String supervisorNodeName) {
        this.supervisorNodeName = supervisorNodeName;
    }
}