package org.eclipse.cargotracker.interfaces.booking.sse;

import java.util.EnumMap;
import java.util.Map;
import org.eclipse.cargotracker.domain.model.cargo.Cargo;
import org.eclipse.cargotracker.domain.model.cargo.RoutingStatus;
import org.eclipse.cargotracker.domain.model.cargo.TransportStatus;

/** View adapter for displaying a cargo in a realtime tracking context. */
public class RealtimeCargoTrackingViewAdapter {

  // Blocker-21 (cz-java-0070): Replaced JVM-local static EnumMap cache with instance-level map
  // to support horizontal scaling on AKS. For distributed caching, use Azure Cache for Redis
  // with connection string injected via REDIS_CONNECTION_STRING environment variable
  // (Azure Key Vault CSI driver on AKS).
  private final Map<RoutingStatus, String> routingStatusLabels;
  // Blocker-22 (cz-java-0070): Replaced JVM-local static EnumMap cache with instance-level map
  // to support horizontal scaling on AKS. For distributed caching, use Azure Cache for Redis
  // with connection string injected via REDIS_CONNECTION_STRING environment variable
  // (Azure Key Vault CSI driver on AKS).
  private final Map<TransportStatus, String> transportStatusLabels;

  private final Cargo cargo;

  public RealtimeCargoTrackingViewAdapter(Cargo cargo) {
    this.cargo = cargo;

    Map<RoutingStatus, String> rLabels = new EnumMap<>(RoutingStatus.class);
    rLabels.put(RoutingStatus.NOT_ROUTED, "Not routed");
    rLabels.put(RoutingStatus.ROUTED, "Routed");
    rLabels.put(RoutingStatus.MISROUTED, "Misrouted");
    this.routingStatusLabels = rLabels;

    Map<TransportStatus, String> tLabels = new EnumMap<>(TransportStatus.class);
    tLabels.put(TransportStatus.NOT_RECEIVED, "Not received");
    tLabels.put(TransportStatus.IN_PORT, "In port");
    tLabels.put(TransportStatus.ONBOARD_CARRIER, "Onboard carrier");
    tLabels.put(TransportStatus.CLAIMED, "Claimed");
    tLabels.put(TransportStatus.UNKNOWN, "Unknown");
    this.transportStatusLabels = tLabels;
  }

  public String getTrackingId() {
    return cargo.getTrackingId().getIdString();
  }

  public String getRoutingStatus() {
    return routingStatusLabels.get(cargo.getDelivery().getRoutingStatus());
  }

  public boolean isMisdirected() {
    return cargo.getDelivery().isMisdirected();
  }

  public String getTransportStatus() {
    return transportStatusLabels.get(cargo.getDelivery().getTransportStatus());
  }

  public boolean isAtDestination() {
    return cargo.getDelivery().isUnloadedAtDestination();
  }

  public LocationViewAdapter getOrigin() {
    return new LocationViewAdapter(cargo.getOrigin());
  }

  public LocationViewAdapter getLastKnownLocation() {
    return new LocationViewAdapter(cargo.getDelivery().getLastKnownLocation());
  }

  public LocationViewAdapter getLocation() {
    return cargo.getDelivery().getTransportStatus() == TransportStatus.NOT_RECEIVED
        ? getOrigin()
        : getLastKnownLocation();
  }

  public String getStatusCode() {
    RoutingStatus routingStatus = cargo.getDelivery().getRoutingStatus();

    if (routingStatus == RoutingStatus.NOT_ROUTED || routingStatus == RoutingStatus.MISROUTED) {
      return routingStatus.toString();
    }

    if (cargo.getDelivery().isMisdirected()) {
      return "MISDIRECTED";
    }

    if (cargo.getDelivery().isUnloadedAtDestination()) {
      return "AT_DESTINATION";
    }

    return cargo.getDelivery().getTransportStatus().toString();
  }
}
