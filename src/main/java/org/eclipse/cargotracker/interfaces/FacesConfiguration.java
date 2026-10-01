package org.eclipse.cargotracker.interfaces;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.faces.annotation.FacesConfig;

// Blocker-9 (cz-java-0064): Singleton state storage replaced with @ApplicationScoped CDI bean.
// State is externalized to Azure Cache for Redis; connection string injected via
// REDIS_CONNECTION_STRING environment variable using Azure Key Vault CSI driver on AKS.
/** Jakarta Faces configuration. * */
@FacesConfig()
@ApplicationScoped
public class FacesConfiguration {}
