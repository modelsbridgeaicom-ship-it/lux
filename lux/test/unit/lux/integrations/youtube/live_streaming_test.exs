defmodule Lux.Integrations.YouTube.LiveStreamingTest do
  use UnitAPICase, async: true

  alias Lux.Integrations.YouTube.LiveStreaming

  describe "plan_broadcast_workflow/1" do
    test "returns a credential-free YouTube live workflow plan" do
      assert {:ok, workflow} =
               LiveStreaming.plan_broadcast_workflow(%{
                 "title" => "Lux market briefing",
                 "scheduled_start_time" => "2026-06-06T12:00:00Z",
                 "privacy_status" => "unlisted",
                 "broadcast_id" => "broadcast-1",
                 "stream_id" => "stream-1",
                 "live_chat_id" => "chat-1",
                 "chat_messages" => [
                   %{"id" => "m1", "author" => "viewer", "text" => "great stream"},
                   %{"id" => "m2", "author" => "spammer", "text" => "click https://bad.test"}
                 ]
               })

      assert workflow.mode == :dry_run
      assert workflow.broadcast.insert.method == :post
      assert workflow.broadcast.insert.url =~ "/liveBroadcasts"
      assert workflow.stream.insert.url =~ "/liveStreams"
      assert workflow.bind.query == %{"id" => "broadcast-1", "streamId" => "stream-1", "part" => "id,contentDetails"}
      assert workflow.live_chat.moderation.requires_review == true
      assert workflow.execution_boundary.live_side_effects == false
    end

    test "validates required scheduling fields" do
      assert {:error, "Missing required YouTube live parameter title"} =
               LiveStreaming.plan_broadcast_workflow(%{
                 scheduled_start_time: "2026-06-06T12:00:00Z"
               })
    end
  end

  describe "health_snapshot/1" do
    test "flags low bitrate, dropped frames, and latency" do
      snapshot =
        LiveStreaming.health_snapshot(%{
          status: "good",
          bitrate_kbps: 1_200,
          min_bitrate_kbps: 2_500,
          dropped_frames: 45,
          max_dropped_frames: 30,
          latency_ms: 12_000,
          max_latency_ms: 10_000
        })

      assert snapshot.status == :attention_required
      assert "low_bitrate" in snapshot.issues
      assert "dropped_frames" in snapshot.issues
      assert "high_latency" in snapshot.issues
    end
  end

  describe "transition_plan/1" do
    test "allows testing to live transition and rejects invalid transitions" do
      allowed =
        LiveStreaming.transition_plan(%{
          broadcast_id: "broadcast-1",
          current_life_cycle_status: "testing",
          target_life_cycle_status: "live"
        })

      assert allowed.allowed == true
      assert allowed.request.query["broadcastStatus"] == "live"

      rejected =
        LiveStreaming.transition_plan(%{
          broadcast_id: "broadcast-1",
          current_life_cycle_status: "complete",
          target_life_cycle_status: "live"
        })

      assert rejected.allowed == false
      assert rejected.guardrails == ["completed broadcasts cannot be transitioned again"]
    end
  end
end
