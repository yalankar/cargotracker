package org.eclipse.cargotracker.application.util;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;

// Blocker-19 (cz-java-0076): Removed GlassFish-specific org.glassfish.jersey.server.ServerProperties
// dependency. Replaced with standard Jakarta REST Application configuration compatible with
// any Jakarta EE container runtime on AKS (Payara, OpenLiberty, WildFly, etc.).
/** Jakarta REST configuration. */
@ApplicationPath("rest")
public class RestConfiguration extends Application {
}
