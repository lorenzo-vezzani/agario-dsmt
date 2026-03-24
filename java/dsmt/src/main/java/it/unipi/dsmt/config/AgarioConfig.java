package it.unipi.dsmt.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "agario")
public class AgarioConfig {

    private String supervisorIp;
    private int supervisorPort;

    public String getSupervisorIp() {
        return supervisorIp;
    }

    public void setSupervisorIp(String supervisorIp) {
        this.supervisorIp = supervisorIp;
    }

    public int getSupervisorPort() {
        return supervisorPort;
    }

    public void setSupervisorPort(int supervisorPort) {
        this.supervisorPort = supervisorPort;
    }
}