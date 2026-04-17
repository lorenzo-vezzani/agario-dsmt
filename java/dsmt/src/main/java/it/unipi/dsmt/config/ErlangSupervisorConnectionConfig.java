package it.unipi.dsmt.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "erlang-supervisor-connection")
public class ErlangSupervisorConnectionConfig {

    private String selfMb;
    private String selfNode;
    private String selfErlangIp;
    private String supervisorCookie;

    public String getSelfMb() {
        return selfMb;
    }

    public void setSelfMb(String selfMb) {
        this.selfMb = selfMb;
    }

    public String getSelfNode() {
        return selfNode;
    }

    public void setSelfNode(String selfNode) {
        this.selfNode = selfNode;
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
}